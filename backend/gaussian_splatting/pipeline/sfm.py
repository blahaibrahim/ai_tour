"""Structure-from-motion over the extracted frames, via pycolmap.

Runs CPU-only, and that is the central cost decision of this pipeline. SfM is
both the slowest stage and by far the likeliest to fail — a capture with too
little parallax, a textureless subject or fast pans simply will not
reconstruct. Failing here costs ~$0.17 of CPU; failing after handing garbage to
an L4 costs several times that and wastes the wall time too. GPU SIFT would be
faster but produces the same result, so the GPU stays out of it.

pycolmap is pinned to 3.10.0. COLMAP 4.x reworked the model around camera rigs,
which changes these call signatures and has known incremental-mapper
regressions with single-camera video input; 3.10 is the last comfortable
version for this use.

The registration check at the end is the point of the whole stage: it is the
gate that stops a bad capture from reaching a billed GPU.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

# Baked into the CPU image at build time by modal_app.py. Sequential matching
# alone never closes the loop on an orbit — the last frames and the first
# frames are temporally distant but spatially adjacent — so vocabulary-tree
# loop detection is what makes a 360 capture reconstruct as one consistent
# model instead of a drifting arc.
VOCAB_TREE_PATH = "/opt/colmap/vocab_tree_flickr100K_words32K.bin"

# Below this, exhaustive matching is cheap enough to be worth its better recall.
EXHAUSTIVE_MAX_FRAMES = 60

# Fraction of extracted frames that must register for the result to be trusted.
MIN_REGISTERED_RATIO = 0.7


class SfmError(RuntimeError):
    """Reconstruction failed or is too poor to be worth training on."""


def _sift_options(num_threads: int):
    import pycolmap

    opts = pycolmap.SiftExtractionOptions()
    opts.num_threads = num_threads
    # Frames are already capped at the pipeline's long edge, so tell COLMAP not
    # to downscale them again — it would throw away the detail we paid to keep.
    opts.max_image_size = 3200
    opts.max_num_features = 8192
    # Both of these roughly triple extraction time for a marginal gain on
    # video, where viewpoint change between neighbouring frames is small.
    opts.estimate_affine_shape = False
    opts.domain_size_pooling = False
    return opts


def _mapper_options(num_threads: int, scene: str):
    import pycolmap

    opts = pycolmap.IncrementalPipelineOptions()
    opts.num_threads = num_threads
    # One video is one scene. Letting COLMAP split into multiple models means
    # the trainer silently gets whichever fragment happened to be largest.
    opts.multiple_models = False
    opts.extract_colors = True
    # Interiors have short baselines and repeated texture (blank walls, tiled
    # floors), so demand more matches before trusting a pair.
    opts.min_num_matches = 30 if scene == "indoor" else 15
    return opts


def run_sfm(
    frames_dir: Path,
    work_dir: Path,
    scene: str = "outdoor",
    num_threads: int = 8,
) -> dict:
    """Feature extraction -> matching -> mapping -> undistortion.

    Leaves an undistorted PINHOLE model at ``work_dir/undistorted`` in the
    layout ``trainer.py`` expects: ``images/`` beside ``sparse/``.
    """
    import pycolmap

    frames_dir, work_dir = Path(frames_dir), Path(work_dir)
    frame_paths = sorted(frames_dir.glob("*.jpg"))
    if not frame_paths:
        raise SfmError(f"no frames under {frames_dir} — run the frames stage first")
    n_frames = len(frame_paths)

    if work_dir.exists():
        shutil.rmtree(work_dir)
    work_dir.mkdir(parents=True)

    database_path = work_dir / "database.db"
    sparse_dir = work_dir / "sparse"
    sparse_dir.mkdir()

    print(f"[sfm] {n_frames} frames, scene={scene}, threads={num_threads}")

    # --- features -----------------------------------------------------------
    # camera_mode=SINGLE is the important flag: every frame came off one lens,
    # so solving for one shared intrinsic instead of N independent ones is both
    # far better conditioned and much faster. OPENCV models the radial and
    # tangential distortion a phone lens actually has.
    print("[sfm] extracting SIFT features (CPU)...")
    pycolmap.extract_features(
        database_path=str(database_path),
        image_path=str(frames_dir),
        camera_mode=pycolmap.CameraMode.SINGLE,
        camera_model="OPENCV",
        sift_options=_sift_options(num_threads),
        device=pycolmap.Device.cpu,
    )

    # --- matching -----------------------------------------------------------
    if n_frames <= EXHAUSTIVE_MAX_FRAMES:
        print(f"[sfm] exhaustive matching ({n_frames * (n_frames - 1) // 2} pairs)...")
        pycolmap.match_exhaustive(
            database_path=str(database_path),
            device=pycolmap.Device.cpu,
        )
        matcher = "exhaustive"
    else:
        match_opts = pycolmap.SequentialMatchingOptions()
        match_opts.overlap = 10
        # Matches frame i against i+1, i+2, i+4, i+8... — multi-scale temporal
        # connectivity for the cost of a linear number of pairs, which keeps
        # slow pans from producing a chain that is locally rigid but globally
        # floppy.
        match_opts.quadratic_overlap = True
        match_opts.loop_detection = True
        match_opts.loop_detection_num_images = 50
        match_opts.vocab_tree_path = VOCAB_TREE_PATH
        if not Path(VOCAB_TREE_PATH).exists():
            # Degrade rather than crash: sequential-only still reconstructs an
            # open trajectory fine, it just cannot close a loop.
            print(f"[sfm] WARNING: no vocab tree at {VOCAB_TREE_PATH}; loop detection off")
            match_opts.loop_detection = False

        print("[sfm] sequential matching with loop detection...")
        pycolmap.match_sequential(
            database_path=str(database_path),
            matching_options=match_opts,
            device=pycolmap.Device.cpu,
        )
        matcher = "sequential+loop"

    # --- mapping ------------------------------------------------------------
    print("[sfm] incremental mapping...")
    reconstructions = pycolmap.incremental_mapping(
        database_path=str(database_path),
        image_path=str(frames_dir),
        output_path=str(sparse_dir),
        options=_mapper_options(num_threads, scene),
    )
    if not reconstructions:
        raise SfmError(
            "COLMAP registered no images at all. The capture has too little "
            "parallax or too little texture to reconstruct — reshoot with a "
            "slower orbit and more overlap between frames."
        )

    best_id = max(reconstructions, key=lambda k: reconstructions[k].num_reg_images())
    rec = reconstructions[best_id]
    n_registered = rec.num_reg_images()
    n_points = rec.num_points3D()
    ratio = n_registered / n_frames

    print(f"[sfm] registered {n_registered}/{n_frames} ({ratio:.0%}), {n_points} points")

    # The gate. Everything downstream of here is GPU-billed.
    if ratio < MIN_REGISTERED_RATIO:
        raise SfmError(
            f"only {n_registered}/{n_frames} frames registered ({ratio:.0%}, "
            f"need {MIN_REGISTERED_RATIO:.0%}). Stopping before the GPU stage. "
            "This is almost always the footage: orbit more slowly, keep the "
            "subject filling the frame, and avoid fast pans."
        )
    if n_points < 1000:
        raise SfmError(
            f"only {n_points} 3D points triangulated — too sparse to seed training."
        )

    model_dir = sparse_dir / str(best_id)

    # --- undistortion -------------------------------------------------------
    # Rewrites images and intrinsics to a pure PINHOLE model. The rasterizer
    # has no distortion model, so this is required, not optional — and it
    # produces exactly the images/ + sparse/ layout colmap_io.load_scene reads.
    undistorted = work_dir / "undistorted"
    print("[sfm] undistorting to PINHOLE...")
    pycolmap.undistort_images(
        output_path=str(undistorted),
        input_path=str(model_dir),
        image_path=str(frames_dir),
        output_type="COLMAP",
    )

    manifest = {
        "frames": n_frames,
        "registered": n_registered,
        "registered_ratio": round(ratio, 4),
        "points3D": n_points,
        "matcher": matcher,
        "scene": scene,
        "model": str(model_dir.relative_to(work_dir)),
    }
    (work_dir / "sfm_manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest
