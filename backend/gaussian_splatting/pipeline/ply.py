"""Writer for the INRIA 3D Gaussian Splatting .ply format.

This is the de-facto interchange format: SuperSplat, PlayCanvas, the
antimatter15 web viewer, Postshot and Blender's splat add-ons all read it. We
emit it rather than a gsplat-native checkpoint so the result is viewable
without any of this code.

Two details are easy to get wrong and produce a file that loads but renders as
garbage:

1. **Values are stored pre-activation.** ``opacity`` is the logit, ``scale`` is
   the log, and ``rot`` is the unnormalized quaternion — exactly the raw
   optimized parameters, not the activated ones used at render time.
2. **``f_rest`` is channel-major.** gsplat holds higher-order spherical
   harmonics as ``[N, K-1, 3]`` (coefficient-major), while the INRIA format
   wants all of red's coefficients, then all of green's, then blue's. That is a
   transpose, and skipping it yields a splat with lurid direction-dependent
   colour fringing.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np


def _header(count: int, n_rest: int) -> bytes:
    props = ["x", "y", "z", "nx", "ny", "nz", "f_dc_0", "f_dc_1", "f_dc_2"]
    props += [f"f_rest_{i}" for i in range(n_rest)]
    props += ["opacity", "scale_0", "scale_1", "scale_2"]
    props += [f"rot_{i}" for i in range(4)]

    lines = ["ply", "format binary_little_endian 1.0", f"element vertex {count}"]
    lines += [f"property float {p}" for p in props]
    lines += ["end_header", ""]
    return "\n".join(lines).encode("ascii")


def write_ply(
    path: Path,
    means: np.ndarray,      # [N,3]
    sh0: np.ndarray,        # [N,1,3]   DC term
    shN: np.ndarray,        # [N,K-1,3] higher-order terms (may be [N,0,3])
    opacities: np.ndarray,  # [N]       raw logits
    scales: np.ndarray,     # [N,3]     raw logs
    quats: np.ndarray,      # [N,4]     raw, wxyz
) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    n = means.shape[0]
    f_dc = sh0.reshape(n, 3)
    # [N, K-1, 3] -> [N, 3, K-1] -> flat. See point 2 in the module docstring.
    f_rest = shN.transpose(0, 2, 1).reshape(n, -1)

    columns = [
        means.astype(np.float32),
        np.zeros((n, 3), np.float32),  # normals: unused by every viewer, but required
        f_dc.astype(np.float32),
        f_rest.astype(np.float32),
        opacities.reshape(n, 1).astype(np.float32),
        scales.astype(np.float32),
        quats.astype(np.float32),
    ]
    table = np.concatenate(columns, axis=1)

    with open(path, "wb") as fh:
        fh.write(_header(n, f_rest.shape[1]))
        # ascontiguousarray because the concatenate above can leave a view
        # whose buffer order does not match the header's property order.
        fh.write(np.ascontiguousarray(table, dtype="<f4").tobytes())

    return path
