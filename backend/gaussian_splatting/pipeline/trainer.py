"""3D Gaussian Splatting training on top of gsplat's core rasterizer.

Written against ``gsplat.rasterization`` + ``gsplat.strategy.DefaultStrategy``
rather than vendoring gsplat's ``examples/simple_trainer.py``. That example is
a fine reference but drags in viser, nerfview, tyro, torchmetrics and
fused-ssim — and fused-ssim needs an nvcc compile at image-build time, which is
exactly the kind of thing that turns a cheap run into an expensive one. The
loop below is the same algorithm with a local SSIM and no extra dependencies.

Optimisation follows the reference 3DGS recipe: L1 + SSIM photometric loss,
per-parameter Adam with an exponentially decayed learning rate on positions,
spherical-harmonic degree warmed up one band at a time, and adaptive
densification/pruning delegated to ``DefaultStrategy``.

The parameters are kept in a ``ParameterDict`` with one optimizer per entry
because that is the convention ``DefaultStrategy`` enforces — it rewrites the
optimizer state in place when it splits, clones and prunes gaussians, so it
needs to find each parameter's optimizer by name.
"""

from __future__ import annotations

import json
import math
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

from . import colmap_io, ply

# Spherical harmonics DC factor: converts between linear RGB and the 0th SH band.
SH_C0 = 0.28209479177387814

MAX_SH_DEGREE = 3
SH_WARMUP_EVERY = 1000  # promote one SH band every N steps

SSIM_LAMBDA = 0.2
SSIM_WINDOW = 11

# Every Nth frame is held out and never trained on, so the reported PSNR is a
# real generalisation number rather than a measure of how well we memorised.
EVAL_EVERY = 8


# ---------------------------------------------------------------------------
# SSIM (local implementation — see module docstring)
# ---------------------------------------------------------------------------

def _ssim_window(size: int, sigma: float, channels: int, device, dtype) -> torch.Tensor:
    coords = torch.arange(size, dtype=dtype, device=device) - (size - 1) / 2
    g = torch.exp(-(coords ** 2) / (2 * sigma ** 2))
    g = g / g.sum()
    kernel = torch.outer(g, g)
    return kernel.expand(channels, 1, size, size).contiguous()


def _ssim(x: torch.Tensor, y: torch.Tensor, window: torch.Tensor) -> torch.Tensor:
    """Mean SSIM over [B,C,H,W] images in 0..1."""
    channels = x.shape[1]
    pad = window.shape[-1] // 2
    c1, c2 = 0.01 ** 2, 0.03 ** 2

    mu_x = F.conv2d(x, window, padding=pad, groups=channels)
    mu_y = F.conv2d(y, window, padding=pad, groups=channels)
    mu_x2, mu_y2, mu_xy = mu_x * mu_x, mu_y * mu_y, mu_x * mu_y

    sigma_x2 = F.conv2d(x * x, window, padding=pad, groups=channels) - mu_x2
    sigma_y2 = F.conv2d(y * y, window, padding=pad, groups=channels) - mu_y2
    sigma_xy = F.conv2d(x * y, window, padding=pad, groups=channels) - mu_xy

    num = (2 * mu_xy + c1) * (2 * sigma_xy + c2)
    den = (mu_x2 + mu_y2 + c1) * (sigma_x2 + sigma_y2 + c2)
    return (num / den).mean()


# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

def _knn_mean_dist(points: torch.Tensor, k: int = 3) -> torch.Tensor:
    """Mean distance to the k nearest other points — the initial gaussian size.

    Chunked, and the reference set is subsampled above a threshold, because a
    full pairwise distance matrix on a few hundred thousand SfM points would be
    tens of gigabytes. Subsampling is harmless here: this is a scale heuristic,
    not a quantity anything downstream depends on precisely.
    """
    n = points.shape[0]
    reference = points
    if n > 200_000:
        idx = torch.randperm(n, device=points.device)[:200_000]
        reference = points[idx]

    # Keep each distance block near 256 MB of float32.
    chunk = max(1, int(256 * 1024 * 1024 / (4 * reference.shape[0])))
    out = []
    for start in range(0, n, chunk):
        block = torch.cdist(points[start:start + chunk], reference)
        # k+1 because a point's nearest neighbour in the reference set is
        # itself whenever it was sampled into it.
        knn = block.topk(k + 1, largest=False).values[:, 1:]
        out.append(knn.mean(dim=-1))
    return torch.cat(out).clamp_min(1e-7)


def _build_splats(
    scene: colmap_io.Scene,
    scene_scale: float,
    scene_type: str,
    device: torch.device,
) -> tuple[torch.nn.ParameterDict, dict[str, torch.optim.Optimizer]]:
    points = torch.from_numpy(scene.points_xyz).float().to(device)
    rgb = torch.from_numpy(scene.points_rgb).float().to(device)

    # Outdoor captures have sky and far-field geometry that SfM never
    # triangulates, so there is nothing there to grow gaussians from and the
    # background ends up as smeared foreground. Seeding random points across a
    # generous volume gives densification something to work with. Interiors are
    # bounded and fully covered by SfM points, so they get none.
    if scene_type == "outdoor":
        extra = 100_000
        centre = points.mean(dim=0) if points.shape[0] else torch.zeros(3, device=device)
        spread = 3.0 * scene_scale
        points = torch.cat([points, centre + spread * (torch.rand(extra, 3, device=device) * 2 - 1)])
        rgb = torch.cat([rgb, torch.rand(extra, 3, device=device)])

    n = points.shape[0]
    scales = torch.log(_knn_mean_dist(points)).unsqueeze(-1).repeat(1, 3)
    quats = torch.zeros(n, 4, device=device)
    quats[:, 0] = 1.0  # identity rotation, wxyz
    opacities = torch.full((n,), math.log(0.1 / 0.9), device=device)  # logit(0.1)

    n_sh = (MAX_SH_DEGREE + 1) ** 2
    sh0 = ((rgb - 0.5) / SH_C0).unsqueeze(1)          # [N,1,3]
    shN = torch.zeros(n, n_sh - 1, 3, device=device)  # [N,15,3]

    splats = torch.nn.ParameterDict({
        "means": torch.nn.Parameter(points),
        "scales": torch.nn.Parameter(scales),
        "quats": torch.nn.Parameter(quats),
        "opacities": torch.nn.Parameter(opacities),
        "sh0": torch.nn.Parameter(sh0),
        "shN": torch.nn.Parameter(shN),
    })

    # Reference 3DGS learning rates. Positions are the only one in world units,
    # so it is the only one scaled by the scene's size.
    lrs = {
        "means": 1.6e-4 * scene_scale,
        "scales": 5e-3,
        "quats": 1e-3,
        "opacities": 5e-2,
        "sh0": 2.5e-3,
        "shN": 2.5e-3 / 20,
    }
    optimizers = {
        name: torch.optim.Adam([{"params": [splats[name]], "lr": lr, "name": name}], eps=1e-15)
        for name, lr in lrs.items()
    }
    return splats, optimizers


# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------

def _export(splats: torch.nn.ParameterDict, path: Path) -> Path:
    with torch.no_grad():
        return ply.write_ply(
            path,
            means=splats["means"].detach().cpu().numpy(),
            sh0=splats["sh0"].detach().cpu().numpy(),
            shN=splats["shN"].detach().cpu().numpy(),
            opacities=splats["opacities"].detach().cpu().numpy(),
            scales=splats["scales"].detach().cpu().numpy(),
            quats=splats["quats"].detach().cpu().numpy(),
        )


def train(
    sfm_dir: Path,
    out_dir: Path,
    max_steps: int = 7_000,
    scene_type: str = "outdoor",
    checkpoint_steps: tuple[int, ...] = (7_000,),
    max_seconds: float | None = None,
    seed: int = 42,
) -> dict:
    """Train a splat from an undistorted COLMAP model. Returns a stats dict.

    ``max_seconds`` is a soft wall-clock budget: on exceeding it the loop stops,
    exports what it has and returns normally. That matters for cost — the hard
    Modal timeout kills the container and loses the run, so relying on it as the
    limit means paying for GPU time and getting nothing back.
    """
    from gsplat import rasterization
    from gsplat.strategy import DefaultStrategy

    if not torch.cuda.is_available():
        raise RuntimeError("training requires a CUDA device")

    sfm_dir, out_dir = Path(sfm_dir), Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    device = torch.device("cuda")
    torch.manual_seed(seed)
    np.random.seed(seed)

    started = time.time()
    scene = colmap_io.load_scene(sfm_dir / "sparse", sfm_dir / "images")

    # Camera-extent scene scale, as in reference 3DGS: the radius of the sphere
    # enclosing all camera centres. Everything in world units keys off this.
    centres = colmap_io.camera_centers(scene.frames)
    scene_scale = float(np.linalg.norm(centres - centres.mean(axis=0), axis=1).max() * 1.1)
    scene_scale = max(scene_scale, 1e-3)

    train_idx = [i for i in range(len(scene.frames)) if i % EVAL_EVERY != 0]
    eval_idx = [i for i in range(len(scene.frames)) if i % EVAL_EVERY == 0]
    if not train_idx:
        raise RuntimeError(f"too few frames ({len(scene.frames)}) to form a train split")

    print(
        f"[train] {len(scene.frames)} views ({len(train_idx)} train / {len(eval_idx)} eval), "
        f"{scene.points_xyz.shape[0]} SfM points, scene_scale={scene_scale:.3f}"
    )

    # Images live on the CPU as uint8 and move to the GPU one at a time. At
    # 1600px a 300-frame scene is ~4 GB as float32 but ~1.3 GB as uint8, and
    # the per-iteration transfer is a rounding error next to the render.
    from PIL import Image

    images = []
    for frame in scene.frames:
        # np.array, not np.asarray: PIL hands back a read-only buffer and
        # torch.from_numpy on one warns and yields a tensor that cannot be pinned.
        arr = np.array(Image.open(frame.path).convert("RGB"), dtype=np.uint8)
        if arr.shape[:2] != (frame.height, frame.width):
            raise RuntimeError(
                f"{frame.name} is {arr.shape[1]}x{arr.shape[0]} but its COLMAP camera "
                f"says {frame.width}x{frame.height}. The sparse model and the images "
                "are out of sync — re-run the sfm stage with --force."
            )
        images.append(torch.from_numpy(arr))

    splats, optimizers = _build_splats(scene, scene_scale, scene_type, device)

    strategy = DefaultStrategy(
        # Densification stops halfway through so the second half is pure
        # refinement of a fixed set — at 7k steps the reference 15k default
        # would never stop at all.
        refine_stop_iter=max_steps // 2,
        refine_start_iter=500,
        refine_every=100,
        reset_every=3000,
        absgrad=True,
        verbose=True,
    )
    strategy.check_sanity(splats, optimizers)
    strategy_state = strategy.initialize_state(scene_scale=scene_scale)

    # Positions decay to 1% of their initial rate over the run — the schedule
    # that lets early steps move gaussians freely and late steps only polish.
    means_sched = torch.optim.lr_scheduler.ExponentialLR(
        optimizers["means"], gamma=0.01 ** (1.0 / max_steps)
    )

    window = _ssim_window(SSIM_WINDOW, 1.5, 3, device, torch.float32)
    viewmats_all = torch.from_numpy(np.stack([f.w2c for f in scene.frames])).float().to(device)
    ks_all = torch.from_numpy(np.stack([f.K for f in scene.frames])).float().to(device)

    checkpoints = sorted({s for s in checkpoint_steps if 0 < s <= max_steps} | {max_steps})
    written: list[str] = []
    order: list[int] = []
    stopped_early = False
    last_step = 0

    for step in range(1, max_steps + 1):
        # Checked on a coarse interval so the clock call is never in the hot
        # path, and before last_step is advanced so the exported filename
        # reflects steps actually completed.
        if max_seconds is not None and step % 100 == 0:
            if time.time() - started > max_seconds:
                print(
                    f"[train] soft budget of {max_seconds:.0f}s reached after step "
                    f"{last_step}/{max_steps} — exporting what we have and stopping."
                )
                stopped_early = True
                break
        last_step = step

        # Shuffled epochs rather than sampling with replacement: every view is
        # seen equally often, which matters when some parts of the scene are
        # covered by only a handful of frames.
        if not order:
            order = [train_idx[i] for i in torch.randperm(len(train_idx)).tolist()]
        i = order.pop()

        frame = scene.frames[i]
        gt = images[i].to(device, non_blocking=True).float().div_(255.0).unsqueeze(0)
        sh_degree = min(step // SH_WARMUP_EVERY, MAX_SH_DEGREE)

        renders, _alphas, info = rasterization(
            means=splats["means"],
            quats=splats["quats"],
            scales=torch.exp(splats["scales"]),
            opacities=torch.sigmoid(splats["opacities"]),
            colors=torch.cat([splats["sh0"], splats["shN"]], dim=1),
            viewmats=viewmats_all[i: i + 1],
            Ks=ks_all[i: i + 1],
            width=frame.width,
            height=frame.height,
            sh_degree=sh_degree,
            packed=True,
            absgrad=True,
            render_mode="RGB",
        )
        rendered = renders.clamp(0.0, 1.0)

        l1 = (rendered - gt).abs().mean()
        ssim = _ssim(rendered.permute(0, 3, 1, 2), gt.permute(0, 3, 1, 2), window)
        loss = (1.0 - SSIM_LAMBDA) * l1 + SSIM_LAMBDA * (1.0 - ssim)

        # Must run before backward: it retains the grad on the 2D means that
        # densification thresholds on.
        strategy.step_pre_backward(
            params=splats, optimizers=optimizers, state=strategy_state, step=step, info=info
        )
        loss.backward()

        # Optimizer first, densification second — this order is load-bearing.
        # step_post_backward splits and prunes gaussians by *replacing* the
        # parameter tensors with fresh ones whose .grad is None, so stepping
        # afterwards would silently discard this iteration's gradient on every
        # refine step. Matches gsplat's own examples/simple_trainer.py.
        for opt in optimizers.values():
            opt.step()
            opt.zero_grad(set_to_none=True)
        means_sched.step()

        strategy.step_post_backward(
            params=splats, optimizers=optimizers, state=strategy_state,
            step=step, info=info, packed=True,
        )

        if step % 500 == 0 or step == 1:
            print(
                f"[train] step {step}/{max_steps}  loss {loss.item():.4f}  "
                f"l1 {l1.item():.4f}  ssim {ssim.item():.4f}  "
                f"gaussians {splats['means'].shape[0]:,}"
            )

        if step in checkpoints:
            path = _export(splats, out_dir / f"point_cloud_{step}.ply")
            written.append(path.name)
            print(f"[train] wrote {path.name} ({path.stat().st_size / 1e6:.1f} MB)")

    # A run cut short by the budget still has to leave something usable behind,
    # otherwise the GPU time is spent for nothing.
    if stopped_early or not written:
        path = _export(splats, out_dir / f"point_cloud_{last_step}.ply")
        written.append(path.name)
        print(f"[train] wrote {path.name} ({path.stat().st_size / 1e6:.1f} MB)")

    psnr = _evaluate(splats, scene, images, viewmats_all, ks_all, eval_idx, out_dir, device)
    elapsed = time.time() - started

    stats = {
        "steps_requested": max_steps,
        "steps_completed": last_step,
        "stopped_early": stopped_early,
        "scene_type": scene_type,
        "views_train": len(train_idx),
        "views_eval": len(eval_idx),
        "scene_scale": round(scene_scale, 4),
        "gaussians": int(splats["means"].shape[0]),
        "eval_psnr": None if psnr is None else round(psnr, 3),
        "gpu_seconds": round(elapsed, 1),
        "ply_files": written,
    }
    (out_dir / "train_stats.json").write_text(json.dumps(stats, indent=2))
    print(f"[train] done in {elapsed / 60:.1f} min — {json.dumps(stats)}")
    return stats


@torch.no_grad()
def _evaluate(
    splats, scene, images, viewmats_all, ks_all, eval_idx, out_dir: Path, device
) -> float | None:
    """PSNR over the held-out views, plus a few gt|render comparison PNGs."""
    if not eval_idx:
        return None
    from PIL import Image

    renders_dir = out_dir / "renders"
    renders_dir.mkdir(exist_ok=True)

    from gsplat import rasterization

    total = 0.0
    for n, i in enumerate(eval_idx):
        frame = scene.frames[i]
        gt = images[i].to(device).float().div_(255.0).unsqueeze(0)
        renders, _, _ = rasterization(
            means=splats["means"],
            quats=splats["quats"],
            scales=torch.exp(splats["scales"]),
            opacities=torch.sigmoid(splats["opacities"]),
            colors=torch.cat([splats["sh0"], splats["shN"]], dim=1),
            viewmats=viewmats_all[i: i + 1],
            Ks=ks_all[i: i + 1],
            width=frame.width,
            height=frame.height,
            sh_degree=MAX_SH_DEGREE,
            packed=True,
            render_mode="RGB",
        )
        rendered = renders.clamp(0.0, 1.0)
        mse = ((rendered - gt) ** 2).mean().item()
        total += -10.0 * math.log10(max(mse, 1e-10))

        # Four side-by-side comparisons are enough to tell "converged" from
        # "diverged" without downloading a multi-hundred-MB ply first.
        if n < 4:
            pair = torch.cat([gt[0], rendered[0]], dim=1).mul(255).byte().cpu().numpy()
            Image.fromarray(pair).save(renders_dir / f"eval_{frame.name}.png")

    return total / len(eval_idx)
