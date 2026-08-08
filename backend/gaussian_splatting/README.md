# Gaussian Splatting from a location video

Turns a video of a place into a 3D Gaussian Splat you can fly around in a
viewer. Standalone experiment — **not** wired into the Flutter app or either
backend. No web endpoints, no Supabase rows, nothing always-on.

All compute runs on Modal. Nothing here runs on your machine except the Modal
client.

```
video ──▶ frames ──▶ COLMAP SfM ──▶ 3DGS training ──▶ point_cloud_7000.ply
          (CPU)        (CPU)            (L4 GPU)
```

## Setup

```bash
pip install -r requirements-local.txt
modal token new          # once, if you haven't already
```

The `gsplat-data` Volume is created on first run.

## Usage

```bash
# 1. Verify both images build and gsplat's CUDA kernels load. ~$0.02.
modal run modal_app.py --stage build

# 2. Upload a clip. Volume path stem becomes the scene name.
modal volume put gsplat-data ./plaza.mp4 /raw/plaza.mp4

# 3. Frames + SfM only — CPU, and the real correctness gate. ~$0.18.
modal run modal_app.py --scene-name plaza --stage sfm

# 4. Train. First GPU spend; --yes is required. ~$0.14.
modal run modal_app.py --scene-name plaza --stage train --yes

# ...or all three at once
modal run modal_app.py --scene-name plaza --yes
```

Fetch and view the result:

```bash
modal volume get gsplat-data /scenes/plaza/output/point_cloud_7000.ply .
```

Drop the `.ply` on [superspl.at/editor](https://superspl.at/editor) — it's the
standard INRIA 3DGS format, so PlayCanvas, Postshot and the antimatter15 viewer
all read it too.

### Flags

| Flag | Default | Notes |
|---|---|---|
| `--scene-name` | *required* | Matches `/raw/<name>.*` in the Volume |
| `--stage` | `all` | `build`, `frames`, `sfm`, `train`, `all` |
| `--scene` | `outdoor` | `outdoor` or `indoor` — see below |
| `--quality` | `draft` | `draft` = 7k iters, `high` = 30k |
| `--max-frames` | preset | 150 draft / 300 high |
| `--iters` | preset | Override the iteration count directly |
| `--force` | off | Redo a stage whose output is already cached |
| `--yes` | off | **Required before anything GPU-billed runs** |

`--scene outdoor` seeds 100k random background gaussians across a wide volume,
because SfM never triangulates sky or far-field geometry and without seeds there
is nothing there for densification to grow from. `--scene indoor` seeds none
(a room is bounded and fully covered by SfM points) and demands more feature
matches per pair, since interiors are full of blank walls and repeated texture.

## Cost

Approximate, at Modal's published rates (L4 $0.000222/s, CPU $0.0000131/core/s,
memory $0.00000222/GiB/s). **Verify at [modal.com/pricing](https://modal.com/pricing)** —
the numbers baked into `modal_app.py`'s estimator are a convenience, not a quote.

| Stage | Resources | Time | Cost |
|---|---|---|---|
| frames | CPU 4c / 8 GiB | ~3 min | ~$0.01 |
| sfm | CPU 8c / 16 GiB | ~20 min | ~$0.17 |
| train (draft, 7k) | L4 / 32 GiB | ~7 min | ~$0.14 |
| train (high, 30k) | L4 / 32 GiB | ~28 min | ~$0.55 |

**~$0.32 per draft run, ~$0.75 per high run**, plus a one-time ~$0.05 image
build. The entrypoint prints an estimate before it spends anything.

### Why it stays cheap

These are mechanisms in the code, not intentions:

- **SfM runs CPU-only.** It's the slowest stage and the one that actually fails
  — bad captures don't reconstruct. Failing there costs $0.17 of CPU instead of
  burning L4 minutes and then producing garbage. The stage refuses to hand off
  unless ≥70% of frames registered.
- **gsplat is pinned to a prebuilt wheel** (`1.5.3+pt24cu124`). Plain
  `pip install gsplat` JIT-compiles CUDA kernels on first import: 5–10 minutes
  of *GPU-billed* time on every cold container. `--stage build` measures the
  first rasterize and warns if this pin ever silently stops matching.
- **Explicit `timeout` on every function** (Modal's default is only 300s) and
  `retries=0`, so a crash never silently re-bills a GPU run.
- **A soft wall-clock budget inside training** exports what it has and stops
  cleanly. The hard Modal timeout is only a backstop — hitting *that* kills the
  container and you pay for the time with nothing to show.
- **`max_containers=1`, `scaledown_window=2`** on the GPU function: no fan-out,
  no idle warm GPU. (Deliberately opposite to `backend/hunyuan2.1`, which keeps
  containers warm because the app is waiting on it. Nothing waits on this.)
- **Stage outputs cached in the Volume and skipped when present**, so a failed
  training run never redoes SfM. `--force` to override.
- **`--yes` gate** before the GPU stage.

## Layout

```
modal_app.py            Modal app: images, volume, 3 stage functions, entrypoint
pipeline/
  frames.py             ffmpeg decode + variance-of-Laplacian sharpness filter
  sfm.py                pycolmap: features → matching → mapping → undistortion
  colmap_io.py          pure-numpy reader for COLMAP's binary model
  ply.py                INRIA 3DGS .ply writer
  trainer.py            gsplat training loop
```

Volume `gsplat-data`:

```
/raw/<scene>.mp4
/scenes/<scene>/frames/frame_00001.jpg ...
/scenes/<scene>/sfm/{database.db, sparse/, undistorted/{images,sparse}}
/scenes/<scene>/output/{point_cloud_*.ply, train_stats.json, renders/}
```

## Pinned versions, and why

| Pin | Reason |
|---|---|
| `pycolmap==3.10.0` | COLMAP 4.x reworked the model around camera rigs, changing these call signatures and introducing incremental-mapper regressions with single-camera video input. |
| `torch==2.4.0+cu124`, Python **3.10** | The newest combination with published gsplat wheels — and `pt24cu124` is **cp310-only**. Bumping Python or torch silently drops you onto the JIT-compiling sdist. |
| `gsplat==1.5.3+pt24cu124` | Prebuilt CUDA kernels. See above. |
| `numpy<2` | pycolmap 3.10's wheels are built against the numpy 1.x ABI. |

## When it doesn't work

Reconstruction quality is mostly a property of the footage, and the pipeline
can't fix a bad capture:

- **"only N/M frames registered"** — the capture has too little parallax or too
  little texture. Orbit more slowly, keep the subject filling the frame, avoid
  fast pans. This error is deliberate and fires before the GPU stage.
- **"every frame was rejected as blurry"** — the whole clip is motion blur. Shoot
  a slower pass; a shorter clip of sharp frames beats a long blurry one.
- **Held-out PSNR under ~20 dB** — check `output/renders/` (side-by-side
  ground-truth vs render PNGs) before spending on `--quality high`.
- **Floaters in the sky on an outdoor scene** — expected at 7k iterations. They
  thin out at 30k, and SuperSplat can box-crop them away.

Capture guidance that actually matters: walk a slow full orbit, keep the subject
in frame the whole way, hold the exposure and focus locked if your camera allows
it, and prefer overcast light. 30–60 seconds is plenty.

## Status

Written but **not yet run** — no stage has been executed on Modal. The
verification ladder in the sections above is ordered cheapest-first for exactly
that reason; start at `--stage build`.
