"""Video -> an evenly spaced set of *sharp* frames for structure-from-motion.

Why not just ``ffmpeg -vf fps=2``: handheld video is full of motion blur, and a
blurry frame is worse than no frame. COLMAP either fails to register it (wasted
matching time) or registers it badly and drags the reconstruction with it. So
this oversamples by ``OVERSAMPLE``x, scores every candidate by
variance-of-Laplacian, and keeps the sharpest candidate from each of
``max_frames`` equal-length time buckets.

Bucketing rather than global top-N matters: a global top-N would happily take
all its frames from the one slow, steady part of the clip and leave the rest of
the scene uncovered. Bucketing keeps temporal spacing even — which is exactly
what the sequential matcher in ``sfm.py`` assumes — while still never picking a
blurry frame when a sharp neighbour exists.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

# Candidates decoded per frame finally kept. 3x gives the sharpness filter a
# real choice inside each bucket without making the decode itself slow.
OVERSAMPLE = 3

# Frames scoring below this fraction of the clip's median sharpness are dropped
# outright. A relative threshold rather than an absolute one because Laplacian
# variance depends on scene texture as much as on focus — an absolute cutoff
# tuned on a brick wall would reject every frame of a smooth interior.
SHARPNESS_FLOOR_RATIO = 0.3

# Long edge used only for the sharpness score. Ranking survives downscaling and
# it makes scoring several hundred candidates take seconds instead of minutes.
SCORE_LONG_EDGE = 640


class FrameExtractionError(RuntimeError):
    pass


def _run(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise FrameExtractionError(
            f"{cmd[0]} failed ({proc.returncode}): {proc.stderr[-2000:]}"
        )
    return proc.stdout


def probe(video_path: Path) -> dict:
    """Duration and pixel dimensions, via ffprobe."""
    out = _run([
        "ffprobe", "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height,duration,avg_frame_rate",
        "-show_entries", "format=duration",
        "-of", "json", str(video_path),
    ])
    meta = json.loads(out)
    if not meta.get("streams"):
        raise FrameExtractionError(f"no video stream in {video_path.name}")
    stream = meta["streams"][0]

    # Stream duration is missing on plenty of phone-recorded containers; the
    # format-level duration is the reliable one.
    duration = float(
        stream.get("duration")
        or meta.get("format", {}).get("duration")
        or 0.0
    )
    if duration <= 0:
        raise FrameExtractionError(f"could not determine duration of {video_path.name}")

    num, _, den = (stream.get("avg_frame_rate") or "0/1").partition("/")
    fps = float(num) / float(den) if float(den or 0) else 0.0

    return {
        "width": int(stream["width"]),
        "height": int(stream["height"]),
        "duration": duration,
        "fps": fps,
    }


def _target_size(width: int, height: int, long_edge: int) -> tuple[int, int]:
    """Scale so the long edge is at most ``long_edge``, keeping both dims even.

    Even dimensions because some encoders reject odd ones, and never upscaling
    because inventing pixels only makes SIFT slower, not better.
    """
    scale = min(1.0, long_edge / max(width, height))
    w = max(2, int(round(width * scale)) // 2 * 2)
    h = max(2, int(round(height * scale)) // 2 * 2)
    return w, h


def _sharpness(path: Path) -> float:
    import cv2

    img = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
    if img is None:
        return 0.0
    h, w = img.shape[:2]
    scale = min(1.0, SCORE_LONG_EDGE / max(h, w))
    if scale < 1.0:
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    return float(cv2.Laplacian(img, cv2.CV_64F).var())


def extract_frames(
    video_path: Path,
    out_dir: Path,
    max_frames: int = 150,
    long_edge: int = 1600,
) -> dict:
    """Decode, score, bucket-select. Returns a manifest dict (also written to disk).

    Output frames are named ``frame_00001.jpg`` in strict temporal order —
    ``sfm.py``'s sequential matcher pairs images by sorted filename, so the
    numbering is part of the contract between the two stages, not cosmetic.
    """
    video_path = Path(video_path)
    out_dir = Path(out_dir)
    if not video_path.exists():
        raise FrameExtractionError(f"no such video: {video_path}")

    meta = probe(video_path)
    width, height = _target_size(meta["width"], meta["height"], long_edge)

    # Never ask for more candidates than the source actually has frames.
    wanted = max_frames * OVERSAMPLE
    sample_fps = wanted / meta["duration"]
    if meta["fps"]:
        sample_fps = min(sample_fps, meta["fps"])

    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    with tempfile.TemporaryDirectory() as tmp:
        cand_dir = Path(tmp)
        _run([
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-i", str(video_path),
            "-vf", f"fps={sample_fps:.6f},scale={width}:{height}",
            "-q:v", "2",
            str(cand_dir / "cand_%05d.jpg"),
        ])

        candidates = sorted(cand_dir.glob("cand_*.jpg"))
        if not candidates:
            raise FrameExtractionError("ffmpeg produced no frames")

        scores = [_sharpness(p) for p in candidates]
        ordered = sorted(scores)
        median = ordered[len(ordered) // 2] or 0.0
        floor = median * SHARPNESS_FLOOR_RATIO

        # Bucket over candidate *index*, which is uniform in time because the
        # decode was at a constant fps.
        n_buckets = min(max_frames, len(candidates))
        chosen: list[tuple[int, Path, float]] = []
        for b in range(n_buckets):
            lo = (b * len(candidates)) // n_buckets
            hi = max(lo + 1, ((b + 1) * len(candidates)) // n_buckets)
            best = max(range(lo, hi), key=lambda i: scores[i])
            if scores[best] >= floor:
                chosen.append((best, candidates[best], scores[best]))

        if not chosen:
            raise FrameExtractionError(
                "every frame was rejected as blurry — the clip is likely all motion blur"
            )

        for n, (_, src, _) in enumerate(chosen, start=1):
            shutil.copyfile(src, out_dir / f"frame_{n:05d}.jpg")

    kept_scores = [s for _, _, s in chosen]
    manifest = {
        "video": video_path.name,
        "source": {k: meta[k] for k in ("width", "height", "duration", "fps")},
        "frame_size": [width, height],
        "sample_fps": round(sample_fps, 4),
        "candidates": len(candidates),
        "kept": len(chosen),
        "dropped_blurry": n_buckets - len(chosen),
        "sharpness": {
            "median_candidate": round(median, 2),
            "min_kept": round(min(kept_scores), 2),
            "max_kept": round(max(kept_scores), 2),
        },
    }
    # Deliberately beside the frames directory, not inside it: COLMAP's image
    # reader enumerates every file under image_path and logs a read failure for
    # anything that isn't an image.
    (out_dir.parent / "frames_manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest
