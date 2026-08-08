"""Gaussian Splatting from a location video, on Modal.

    modal volume put gsplat-data ./clip.mp4 /raw/plaza.mp4
    modal run modal_app.py --scene-name plaza --yes
    modal volume get gsplat-data /scenes/plaza/output/point_cloud_7000.ply .

Three stages, three functions, one Volume. The split is a cost decision:
structure-from-motion is the slowest and by far the likeliest stage to fail, so
it runs **CPU-only**. A capture that cannot reconstruct fails for ~$0.17 of CPU
instead of burning L4 minutes and then producing garbage.

Deliberately unlike ``backend/hunyuan2.1/api.py``: no web endpoints, no proxy
auth, no warm containers. That app serves the Flutter client and wants a
pipeline resident in memory for latency. This one is a batch tool nobody is
waiting on, so an idle warm GPU would be pure burn.

Cost guardrails, all load-bearing:

* Prebuilt gsplat wheels, pinned. ``pip install gsplat`` from PyPI JIT-compiles
  its CUDA kernels on first import — 5-10 minutes of *GPU-billed* time on every
  cold container. This pin is the difference between ~$0.14 and ~$0.30 a run.
  ``pt24cu124`` is the newest published combination and it is **cp310-only**,
  which is why the GPU image pins Python 3.10.
* Explicit ``timeout`` everywhere (Modal's default is only 300s) and
  ``retries=0``, so a crash never silently re-bills a GPU run.
* A soft wall-clock budget inside training that exports and stops early, so the
  hard Modal timeout is a backstop rather than the actual limit.
* ``max_containers=1`` and ``scaledown_window`` of seconds on the GPU function.
* Stage outputs are cached in the Volume and skipped when present, so a failed
  training run never redoes SfM.
* The GPU stage refuses to start without ``--yes``.
"""

from __future__ import annotations

import modal

APP_NAME = "gsplat-pipeline"
DATA = "/data"

VOCAB_DIR = "/opt/colmap"
VOCAB_FILE = f"{VOCAB_DIR}/vocab_tree_flickr100K_words32K.bin"
VOCAB_URL = (
    "https://github.com/colmap/colmap/releases/download/3.11.1/"
    "vocab_tree_flickr100K_words32K.bin"
)

# Modal's published rates, used only to print an estimate before spending.
# Verify against modal.com/pricing — these are not authoritative.
USD_PER_L4_SEC = 0.000222
USD_PER_CORE_SEC = 0.0000131
USD_PER_GIB_SEC = 0.00000222

SFM_CPU = 8
SFM_MEM_GIB = 16
TRAIN_MEM_GIB = 32

PRESETS = {
    # Visibly good, a few floaters, fast enough to iterate on.
    "draft": {"iters": 7_000, "max_frames": 150, "budget_s": 1_200},
    # Reference-quality; roughly 4x the GPU time.
    "high": {"iters": 30_000, "max_frames": 300, "budget_s": 3_300},
}

LONG_EDGE = 1600

app = modal.App(APP_NAME)
vol = modal.Volume.from_name("gsplat-data", create_if_missing=True)

# --- images -----------------------------------------------------------------
# pycolmap 3.10.0 rather than 4.x: COLMAP 4 reworked the model around camera
# rigs, changing these call signatures and introducing incremental-mapper
# regressions with single-camera video input.
sfm_image = (
    modal.Image.debian_slim(python_version="3.10")
    .apt_install("ffmpeg", "curl", "libgomp1", "libglib2.0-0")
    .pip_install(
        "pycolmap==3.10.0",
        "numpy<2",
        "opencv-python-headless==4.10.0.84",
        "pillow",
    )
    .run_commands(
        f"mkdir -p {VOCAB_DIR}",
        f"curl -fsSL --retry 3 -o {VOCAB_FILE} {VOCAB_URL}",
    )
    .add_local_python_source("pipeline")
)

# No nvidia/cuda base image needed: the pip torch cu124 wheels ship the CUDA
# runtime, and the prebuilt gsplat wheel needs no nvcc. Far smaller and faster
# to build than hunyuan2.1/Dockerfile.
train_image = (
    modal.Image.debian_slim(python_version="3.10")
    .pip_install("torch==2.4.0", index_url="https://download.pytorch.org/whl/cu124")
    .pip_install("ninja", "jaxtyping", "rich>=12", "numpy<2", "pillow")
    # --no-deps because the gsplat wheel index hosts only gsplat; letting pip
    # resolve dependencies against it would fail to find jaxtyping/rich, and
    # letting it reach PyPI risks pulling the JIT-compiling sdist instead.
    .pip_install(
        "gsplat==1.5.3+pt24cu124",
        index_url="https://docs.gsplat.studio/whl",
        extra_options="--no-deps",
    )
    .add_local_python_source("pipeline")
)


# ---------------------------------------------------------------------------
# Stage 1 — frames (CPU)
# ---------------------------------------------------------------------------

@app.function(
    image=sfm_image,
    volumes={DATA: vol},
    cpu=4,
    memory=8192,
    timeout=1200,
    retries=0,
)
def extract_frames(scene_name: str, max_frames: int) -> dict:
    from pathlib import Path

    from pipeline import frames

    raw = sorted(Path(f"{DATA}/raw").glob(f"{scene_name}.*"))
    if not raw:
        raise FileNotFoundError(
            f"no video at {DATA}/raw/{scene_name}.* — upload one first with:\n"
            f"  modal volume put gsplat-data <local.mp4> /raw/{scene_name}.mp4"
        )

    manifest = frames.extract_frames(
        video_path=raw[0],
        out_dir=Path(f"{DATA}/scenes/{scene_name}/frames"),
        max_frames=max_frames,
        long_edge=LONG_EDGE,
    )
    vol.commit()
    print(f"[frames] {manifest}")
    return manifest


# ---------------------------------------------------------------------------
# Stage 2 — SfM (CPU, on purpose)
# ---------------------------------------------------------------------------

@app.function(
    image=sfm_image,
    volumes={DATA: vol},
    cpu=SFM_CPU,
    memory=SFM_MEM_GIB * 1024,
    timeout=3600,
    retries=0,
)
def run_sfm(scene_name: str, scene_type: str) -> dict:
    from pathlib import Path

    from pipeline import sfm

    manifest = sfm.run_sfm(
        frames_dir=Path(f"{DATA}/scenes/{scene_name}/frames"),
        work_dir=Path(f"{DATA}/scenes/{scene_name}/sfm"),
        scene=scene_type,
        num_threads=SFM_CPU,
    )
    vol.commit()
    print(f"[sfm] {manifest}")
    return manifest


# ---------------------------------------------------------------------------
# Stage 3 — training (GPU)
# ---------------------------------------------------------------------------

@app.function(
    image=train_image,
    gpu="L4",
    volumes={DATA: vol},
    memory=TRAIN_MEM_GIB * 1024,
    # Hard backstop only. The real limit is the soft budget passed into
    # trainer.train(), which exports what it has and stops cleanly.
    timeout=3900,
    retries=0,
    max_containers=1,
    # Nothing is waiting on this, so never hold a GPU idle between calls.
    scaledown_window=2,
)
def train(scene_name: str, scene_type: str, iters: int, budget_s: int) -> dict:
    from pathlib import Path

    from pipeline import trainer

    stats = trainer.train(
        sfm_dir=Path(f"{DATA}/scenes/{scene_name}/sfm/undistorted"),
        out_dir=Path(f"{DATA}/scenes/{scene_name}/output"),
        max_steps=iters,
        scene_type=scene_type,
        # Always leave a usable ply at 7k, even on a long run that gets cut off.
        checkpoint_steps=(7_000,),
        max_seconds=budget_s,
    )
    vol.commit()
    return stats


# ---------------------------------------------------------------------------
# Image smoke tests (rung 1 of the verification ladder)
# ---------------------------------------------------------------------------

@app.function(image=sfm_image, timeout=600, retries=0)
def verify_cpu_image() -> dict:
    import os
    import subprocess

    import cv2
    import numpy
    import pycolmap

    ffmpeg = subprocess.run(["ffmpeg", "-version"], capture_output=True, text=True)
    return {
        "pycolmap": getattr(pycolmap, "__version__", "n/a"),
        "colmap": str(getattr(pycolmap, "COLMAP_version", "n/a")),
        # Must be False. A CUDA-enabled build here would mean device=cpu is
        # doing something other than what this pipeline assumes.
        "colmap_has_cuda": bool(getattr(pycolmap, "has_cuda", False)),
        "opencv": cv2.__version__,
        "numpy": numpy.__version__,
        "ffmpeg": ffmpeg.stdout.splitlines()[0] if ffmpeg.stdout else "MISSING",
        "vocab_tree": os.path.exists(VOCAB_FILE),
        # Confirms the pycolmap entry points this pipeline calls actually exist
        # at the pinned version, which is the whole risk of a pinned binding.
        "api_ok": all(
            hasattr(pycolmap, name)
            for name in (
                "extract_features", "match_exhaustive", "match_sequential",
                "incremental_mapping", "undistort_images",
                "SiftExtractionOptions", "SequentialMatchingOptions",
                "IncrementalPipelineOptions", "CameraMode", "Device",
            )
        ),
    }


@app.function(
    image=train_image,
    gpu="L4",
    timeout=600,
    retries=0,
    max_containers=1,
    scaledown_window=2,
)
def verify_gpu_image() -> dict:
    """Actually rasterize once — that is what proves no JIT compile happens."""
    import time

    import torch
    from gsplat import rasterization

    started = time.time()
    n = 100
    means = torch.randn(n, 3, device="cuda")
    quats = torch.zeros(n, 4, device="cuda")
    quats[:, 0] = 1.0
    scales = torch.full((n, 3), 0.1, device="cuda")
    opacities = torch.full((n,), 0.5, device="cuda")
    colors = torch.rand(n, 1, 3, device="cuda")
    viewmats = torch.eye(4, device="cuda").unsqueeze(0)
    viewmats[0, 2, 3] = 5.0
    Ks = torch.tensor([[[100.0, 0, 32.0], [0, 100.0, 32.0], [0, 0, 1.0]]], device="cuda")

    out, _, _ = rasterization(
        means=means, quats=quats, scales=scales, opacities=opacities,
        colors=colors, viewmats=viewmats, Ks=Ks, width=64, height=64, sh_degree=0,
    )
    elapsed = time.time() - started

    import gsplat

    return {
        "torch": torch.__version__,
        "cuda": torch.version.cuda,
        "gpu": torch.cuda.get_device_name(0),
        "gsplat": gsplat.__version__,
        "render_shape": list(out.shape),
        "first_rasterize_seconds": round(elapsed, 2),
        # A cold prebuilt wheel rasterizes in seconds. Tens of seconds or more
        # means the CUDA extension was compiled at runtime and the wheel pin
        # has silently stopped matching the installed torch.
        "jit_compiled": elapsed > 60,
    }


# ---------------------------------------------------------------------------
# Local driver
# ---------------------------------------------------------------------------

def _count(path: str) -> int:
    """Number of entries at a Volume path; 0 if the path does not exist.

    Narrowly scoped on purpose. A blanket ``except`` here would turn an auth or
    connectivity failure into "nothing is cached", which silently redoes the
    20-minute SfM stage and doubles the bill — so anything that isn't a genuine
    missing path is surfaced instead of swallowed.
    """
    from modal.exception import NotFoundError

    try:
        return len(vol.listdir(path))
    except (NotFoundError, FileNotFoundError):
        return 0
    except Exception as exc:
        raise SystemExit(
            f"could not read the gsplat-data volume at {path}: {exc!r}\n"
            "Refusing to continue, since treating this as an empty cache would "
            "redo work you have already paid for."
        )


def _estimate(iters: int, run_frames: bool, run_sfm_stage: bool) -> tuple[float, str]:
    lines = []
    total = 0.0

    if run_frames:
        cost = 4 * USD_PER_CORE_SEC * 180 + 8 * USD_PER_GIB_SEC * 180
        total += cost
        lines.append(f"  frames   ~3 min   CPU 4c/8GiB      ~${cost:.2f}")
    if run_sfm_stage:
        secs = 1200
        cost = SFM_CPU * USD_PER_CORE_SEC * secs + SFM_MEM_GIB * USD_PER_GIB_SEC * secs
        total += cost
        lines.append(f"  sfm      ~20 min  CPU {SFM_CPU}c/{SFM_MEM_GIB}GiB     ~${cost:.2f}")
    if iters:
        # ~1100 steps/min on an L4 at 1600px is the working assumption.
        secs = iters / 1100 * 60
        cost = secs * USD_PER_L4_SEC + TRAIN_MEM_GIB * USD_PER_GIB_SEC * secs
        total += cost
        lines.append(f"  train    ~{secs / 60:.0f} min  GPU L4/{TRAIN_MEM_GIB}GiB     ~${cost:.2f}")

    lines.append(f"  {'total':<8} {'':>26} ~${total:.2f}")
    return total, "\n".join(lines)


@app.local_entrypoint()
def main(
    scene_name: str = "",
    stage: str = "all",
    scene: str = "outdoor",
    quality: str = "draft",
    max_frames: int = 0,
    iters: int = 0,
    force: bool = False,
    yes: bool = False,
):
    """Drive the pipeline.

    --stage build            verify both images (rung 1; ~$0.02, touches an L4)
    --stage frames|sfm|train run one stage
    --stage all              frames -> sfm -> train

    --scene outdoor|indoor   SfM and background defaults
    --quality draft|high     7k iterations (default) or 30k
    --force                  redo a stage whose output already exists
    --yes                    required before anything GPU-billed runs
    """
    if stage == "build":
        print("Verifying CPU image...")
        for k, v in verify_cpu_image.remote().items():
            print(f"  {k}: {v}")
        print("\nVerifying GPU image (this starts an L4, ~$0.01)...")
        gpu = verify_gpu_image.remote()
        for k, v in gpu.items():
            print(f"  {k}: {v}")
        if gpu.get("jit_compiled"):
            print(
                "\n  WARNING: the first rasterize was slow, which means gsplat "
                "compiled its CUDA kernels at runtime. Re-check the wheel pin "
                "against the installed torch before running training."
            )
        return

    if stage not in ("all", "frames", "sfm", "train"):
        raise SystemExit(f"unknown --stage {stage!r}")
    if not scene_name:
        raise SystemExit("--scene-name is required")
    if scene not in ("outdoor", "indoor"):
        raise SystemExit(f"--scene must be outdoor or indoor, got {scene!r}")
    if quality not in PRESETS:
        raise SystemExit(f"--quality must be one of {sorted(PRESETS)}")

    preset = PRESETS[quality]
    n_frames = max_frames or preset["max_frames"]
    n_iters = iters or preset["iters"]
    base = f"/scenes/{scene_name}"

    want_frames = stage in ("all", "frames")
    want_sfm = stage in ("all", "sfm")
    want_train = stage in ("all", "train")

    # Cached-stage skipping: a failed training run must never redo SfM.
    have_frames = _count(f"{base}/frames")
    have_sfm = _count(f"{base}/sfm/undistorted/images")
    if want_frames and have_frames and not force:
        print(f"[skip] {have_frames} frames already present (--force to redo)")
        want_frames = False
    if want_sfm and have_sfm and not force:
        print(f"[skip] SfM already done, {have_sfm} undistorted images (--force to redo)")
        want_sfm = False

    # Fail before spending, not during. Without this, `--stage train` on a scene
    # that has no SfM output starts a billed L4 that can only crash in
    # load_scene — the single most avoidable way to waste GPU money here.
    if want_sfm and not want_frames and not have_frames:
        raise SystemExit(
            f"no frames at {base}/frames — run --stage frames first (or --stage all)."
        )
    if want_train and not want_sfm and not have_sfm:
        raise SystemExit(
            f"no SfM output at {base}/sfm/undistorted — run --stage sfm first "
            "(or --stage all). Refusing to start a GPU container that would only fail."
        )

    total, table = _estimate(n_iters if want_train else 0, want_frames, want_sfm)
    print(
        f"\nscene={scene_name}  type={scene}  quality={quality}  "
        f"frames<={n_frames}  iters={n_iters}\n\n"
        f"Estimated Modal spend (approximate — verify at modal.com/pricing):\n{table}\n"
    )

    if want_train and not yes:
        raise SystemExit(
            "Refusing to start the GPU stage without --yes.\n"
            "Re-run with --yes to spend the estimate above, or use "
            "--stage sfm to stop before the GPU."
        )

    if want_frames:
        print("=== frames ===")
        extract_frames.remote(scene_name, n_frames)
    if want_sfm:
        print("=== sfm ===")
        run_sfm.remote(scene_name, scene)
    if want_train:
        print("=== train ===")
        stats = train.remote(scene_name, scene, n_iters, preset["budget_s"])
        print(f"\n{stats}")

        psnr = stats.get("eval_psnr")
        if psnr is not None and psnr < 20:
            print(
                f"\n  NOTE: held-out PSNR is {psnr:.1f} dB, below the ~20 dB a healthy "
                "draft reaches. Check output/renders/ before spending on --quality high."
            )

        # Name the files that were actually written — a budget-truncated run
        # ends on a step number nobody asked for.
        for name in stats.get("ply_files", []):
            print(f"\n  modal volume get gsplat-data {base}/output/{name} .")
        print("\nDrop the .ply on https://superspl.at/editor to view it.")
