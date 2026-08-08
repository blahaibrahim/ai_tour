"""Stage implementations for the Gaussian-splatting pipeline.

Kept out of ``modal_app.py`` so each module can be read on its own, and so the
Modal entrypoint stays a thin layer of scheduling and cost policy.

Nothing here imports Modal, and nothing at module scope imports a heavy
dependency: ``frames``/``sfm`` need OpenCV and pycolmap (CPU image only),
``trainer`` needs torch and gsplat (GPU image only), and the local entrypoint
must be able to import neither. Heavy imports therefore live inside functions.
"""
