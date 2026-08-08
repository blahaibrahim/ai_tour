"""Minimal reader for COLMAP's binary sparse model, in pure numpy.

This exists so the GPU image doesn't need pycolmap. pycolmap is a ~200 MB
dependency that pulls in Ceres and a SIFT stack the trainer will never call,
and keeping it out of the CUDA image keeps that image small and its build fast.
Reading three well-specified binary files is cheaper than carrying the library.

Format reference: ``colmap/scripts/python/read_write_model.py``.

Only the subset the trainer needs is implemented, and it assumes the model has
already been through ``undistort_images`` — so every camera is PINHOLE and
``load_scene`` rejects anything else rather than silently ignoring distortion
coefficients it isn't applying.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass
class Frame:
    """One registered image: its pixels' path, intrinsics and world-to-camera pose."""

    name: str
    path: Path
    K: np.ndarray  # [3,3] float64
    w2c: np.ndarray  # [4,4] float64
    width: int
    height: int


@dataclass
class Scene:
    frames: list[Frame]
    points_xyz: np.ndarray  # [P,3] float32
    points_rgb: np.ndarray  # [P,3] float32 in 0..1


def _read(fh, fmt: str):
    size = struct.calcsize(fmt)
    data = fh.read(size)
    if len(data) != size:
        raise EOFError(f"truncated COLMAP model: wanted {size} bytes, got {len(data)}")
    return struct.unpack(fmt, data)


def read_cameras_binary(path: Path) -> dict[int, dict]:
    # COLMAP's model_id -> (name, number of params). Only the models that can
    # come out of undistortion are listed; anything else raises in load_scene.
    models = {
        0: ("SIMPLE_PINHOLE", 3),
        1: ("PINHOLE", 4),
        2: ("SIMPLE_RADIAL", 4),
        3: ("RADIAL", 5),
        4: ("OPENCV", 8),
    }
    cameras: dict[int, dict] = {}
    with open(path, "rb") as fh:
        (count,) = _read(fh, "<Q")
        for _ in range(count):
            cam_id, model_id, width, height = _read(fh, "<iiQQ")
            if model_id not in models:
                raise ValueError(f"unsupported COLMAP camera model id {model_id}")
            model_name, n_params = models[model_id]
            params = _read(fh, "<" + "d" * n_params)
            cameras[cam_id] = {
                "model": model_name,
                "width": int(width),
                "height": int(height),
                "params": np.array(params, dtype=np.float64),
            }
    return cameras


def read_images_binary(path: Path) -> dict[int, dict]:
    images: dict[int, dict] = {}
    with open(path, "rb") as fh:
        (count,) = _read(fh, "<Q")
        for _ in range(count):
            image_id, qw, qx, qy, qz, tx, ty, tz, cam_id = _read(fh, "<idddddddi")

            name_bytes = bytearray()
            while True:
                char = fh.read(1)
                if char == b"\x00" or char == b"":
                    break
                name_bytes += char

            # The 2D point track follows; the trainer doesn't use it, so skip
            # over it by size rather than parsing it.
            (n_points2d,) = _read(fh, "<Q")
            fh.seek(n_points2d * struct.calcsize("<ddq"), 1)

            images[image_id] = {
                "name": name_bytes.decode("utf-8"),
                "qvec": np.array([qw, qx, qy, qz], dtype=np.float64),
                "tvec": np.array([tx, ty, tz], dtype=np.float64),
                "camera_id": cam_id,
            }
    return images


def read_points3d_binary(path: Path) -> tuple[np.ndarray, np.ndarray]:
    xyz: list[tuple[float, float, float]] = []
    rgb: list[tuple[int, int, int]] = []
    with open(path, "rb") as fh:
        (count,) = _read(fh, "<Q")
        for _ in range(count):
            _pid, x, y, z, r, g, b, _err = _read(fh, "<QdddBBBd")
            (track_len,) = _read(fh, "<Q")
            fh.seek(track_len * struct.calcsize("<ii"), 1)
            xyz.append((x, y, z))
            rgb.append((r, g, b))

    if not xyz:
        return np.zeros((0, 3), np.float32), np.zeros((0, 3), np.float32)
    return (
        np.asarray(xyz, dtype=np.float32),
        np.asarray(rgb, dtype=np.float32) / 255.0,
    )


def qvec_to_rotmat(q: np.ndarray) -> np.ndarray:
    """COLMAP stores rotation as a (w, x, y, z) unit quaternion."""
    w, x, y, z = q / np.linalg.norm(q)
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
    ], dtype=np.float64)


def load_scene(sparse_dir: Path, images_dir: Path) -> Scene:
    """Read an undistorted COLMAP model into camera poses + a seed point cloud."""
    sparse_dir, images_dir = Path(sparse_dir), Path(images_dir)

    cameras = read_cameras_binary(sparse_dir / "cameras.bin")
    images = read_images_binary(sparse_dir / "images.bin")
    points_xyz, points_rgb = read_points3d_binary(sparse_dir / "points3D.bin")

    frames: list[Frame] = []
    # Sorted by filename so the held-out eval split is deterministic across
    # runs — image_id ordering out of COLMAP is registration order, which is not.
    for image in sorted(images.values(), key=lambda im: im["name"]):
        cam = cameras[image["camera_id"]]
        if cam["model"] == "PINHOLE":
            fx, fy, cx, cy = cam["params"]
        elif cam["model"] == "SIMPLE_PINHOLE":
            f, cx, cy = cam["params"]
            fx = fy = f
        else:
            raise ValueError(
                f"camera model {cam['model']} still has distortion — "
                "load_scene expects the undistorted model written by undistort_images"
            )

        frame_path = images_dir / image["name"]
        if not frame_path.exists():
            continue

        w2c = np.eye(4, dtype=np.float64)
        w2c[:3, :3] = qvec_to_rotmat(image["qvec"])
        w2c[:3, 3] = image["tvec"]

        frames.append(Frame(
            name=image["name"],
            path=frame_path,
            K=np.array([[fx, 0, cx], [0, fy, cy], [0, 0, 1]], dtype=np.float64),
            w2c=w2c,
            width=cam["width"],
            height=cam["height"],
        ))

    if not frames:
        raise ValueError(f"no registered images found under {images_dir}")
    return Scene(frames=frames, points_xyz=points_xyz, points_rgb=points_rgb)


def camera_centers(frames: list[Frame]) -> np.ndarray:
    """Camera positions in world space: C = -R^T t."""
    return np.stack([
        -f.w2c[:3, :3].T @ f.w2c[:3, 3] for f in frames
    ]).astype(np.float64)
