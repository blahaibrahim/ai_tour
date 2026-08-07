"""Hunyuan3D 2.1 on Modal — async job model (docs/backend/06).

Three surfaces:

* ``submit``   — a fast, proxy-authed web endpoint. Validates, calls
  ``Generator.generate.spawn(...)`` and returns ``{"call_id": ...}`` in well
  under a second. This is what ``backend/server/routes/models.py`` POSTs to
  (``MODAL_SUBMIT_URL``), with ``{"job_id", "image_url", "input_path"}``.
* ``Generator`` — the GPU worker. Loads both pipelines **once per container**
  (``@modal.enter()``) rather than once per request, runs the job in a
  per-request temp dir, uploads the ``.glb`` to Supabase Storage and then
  **patches ``model_jobs`` itself**. That patch is what the Flutter client's
  Realtime subscription on ``model_jobs`` is waiting for — nothing polls.
* ``status``   — a non-blocking poll on a call id, used only to reconcile a
  job whose push never landed.

The previous version was a single synchronous endpoint that took a multipart
upload, held the connection open for the whole multi-minute run and never
touched ``model_jobs``. Both halves of that broke the app: the Flask route
POSTs JSON to ``/submit`` (404 — no such endpoint), and even the runs that did
complete left their job row stuck in ``processing`` until the reconcile cron
marked it ``timeout``, so the folder never advanced past "Generating 3D…".

Storage layout matters here: the ``models`` bucket's RLS policy is
``(storage.foldername(name))[1] = auth.uid()``, so the object **must** be
written to ``{user_id}/{artifact_id}.glb`` or the owner cannot read back their
own model. ``model_jobs.output_path`` stores it with the bucket prefix
(``models/{user_id}/{artifact_id}.glb``) because ``MediaCache.getModel`` on the
client strips exactly that prefix.
"""

import io
import os
import time
import traceback
from datetime import datetime, timezone

import modal

app = modal.App("hunyuan3d-api")

REPO = "/workspace/Hunyuan3D-2.1"

hf_cache = modal.Volume.from_name("hf-cache")
hy3dgen_cache = modal.Volume.from_name("hy3dgen-cache")
u2net_cache = modal.Volume.from_name("u2net-cache", create_if_missing=True)

# setuptools is pinned in the image rather than `pip install`-ed at request
# time (as the old inline pipeline did): a network hop to PyPI in the hot path
# fails the job whenever PyPI is slow, and it is the same pin on every run.
image = (
    modal.Image.from_dockerfile("Dockerfile")
    .pip_install("fastapi", "python-multipart", "supabase", "pillow", "requests", "setuptools<70.0.0")
)

MAX_IMAGE_BYTES = 10 * 1024 * 1024

# Error codes the client has copy for (lib/models/location.dart's
# modelFailureMessages). Anything not in this set is reported as "internal",
# with the specific cause left in the Modal logs.
CLIENT_ERROR_CODES = {"no_subject", "timeout", "gpu_oom", "internal"}

# A failure that isn't the user's fault gets the credit back. `no_subject`
# does not — it consumed real GPU time and the user can fix the input by
# retaking the photo (docs/backend/06).
REFUNDABLE = {"timeout", "gpu_oom", "internal"}


# ---------------------------------------------------------------------------
# Supabase helpers (service role — this runs on the server side of the trust
# boundary, never in the app)
# ---------------------------------------------------------------------------

def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _supabase():
    from supabase import create_client

    return create_client(
        os.environ["SUPABASE_URL"],
        os.environ["SUPABASE_SERVICE_ROLE_KEY"],
    )


def _fetch_job(sb, job_id: str) -> dict | None:
    res = (
        sb.table("model_jobs")
        .select("id,user_id,artifact_id,input_path,status")
        .eq("id", job_id)
        .limit(1)
        .execute()
    )
    return res.data[0] if res.data else None


def _finish_job(sb, job_id: str, user_id: str | None, error_code: str) -> dict:
    """Mark a job failed and refund the credit when the cause was ours."""
    code = error_code if error_code in CLIENT_ERROR_CODES else "internal"
    try:
        sb.table("model_jobs").update(
            {
                "status": "failed",
                "error_code": code,
                "finished_at": _now(),
            }
        ).eq("id", job_id).execute()
    except Exception:
        traceback.print_exc()

    if user_id and code in REFUNDABLE:
        try:
            sb.rpc("refund_model_credit", {"p_user": user_id}).execute()
        except Exception:
            traceback.print_exc()

    return {"status": "failed", "error_code": code, "detail": error_code}


def _download_image(sb, job: dict, image_url: str | None) -> bytes:
    """Storage-first, signed-URL second.

    The signed URL the Flask route mints is only good for ten minutes, and a
    job can sit behind other jobs on the GPU for longer than that — so the
    service-role download is the primary path and cannot expire. The URL is
    kept as a fallback for the case where the object moved.
    """
    input_path = job.get("input_path") or ""
    if input_path.startswith("captures/"):
        try:
            return sb.storage.from_("captures").download(input_path[len("captures/"):])
        except Exception:
            traceback.print_exc()

    if not image_url:
        raise RuntimeError("no image source: neither input_path nor image_url resolved")

    import requests

    resp = requests.get(image_url, timeout=60)
    resp.raise_for_status()
    return resp.content


# ---------------------------------------------------------------------------
# GPU worker
# ---------------------------------------------------------------------------

@app.cls(
    image=image,
    gpu="L4",
    # 15 min is the ceiling a real job should ever need; the old 3600 meant a
    # hung run held an L4 for an hour before anyone found out.
    timeout=900,
    # Keep a loaded container warm between jobs so consecutive runs skip the
    # (multi-minute) pipeline load entirely.
    scaledown_window=300,
    max_containers=4,
    secrets=[modal.Secret.from_name("supabase-service")],
    volumes={
        "/root/.cache/huggingface": hf_cache,
        "/root/.cache/hy3dgen": hy3dgen_cache,
        "/root/.u2net": u2net_cache,
    },
)
class Generator:

    @modal.enter()
    def load(self):
        """Runs once per container, not once per request.

        A failure here is captured rather than raised: if it propagated, the
        container would just be retried and the job row would sit in
        `processing` until the reconcile cron timed it out 20 minutes later.
        Storing it lets `generate` fail the job immediately with a real cause.
        """
        self.load_error = None
        try:
            import sys

            # Both pipelines resolve their checkpoint/config paths relative to
            # the repo root (`hy3dpaint/ckpt/...`), so the cwd is part of the
            # contract, not incidental.
            os.chdir(REPO)
            for path in (REPO, f"{REPO}/hy3dshape", f"{REPO}/hy3dpaint"):
                if path not in sys.path:
                    sys.path.insert(0, path)

            try:
                from torchvision_fix import apply_fix

                apply_fix()
            except Exception:
                pass

            from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
            from textureGenPipeline import Hunyuan3DPaintPipeline, Hunyuan3DPaintConfig
            from rembg import new_session

            self.rembg_session = new_session("u2net")
            self.shape = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
                "tencent/Hunyuan3D-2.1"
            )

            conf = Hunyuan3DPaintConfig(6, 512)
            conf.realesrgan_ckpt_path = "hy3dpaint/ckpt/RealESRGAN_x4plus.pth"
            conf.multiview_cfg_path = "hy3dpaint/cfgs/hunyuan-paint-pbr.yaml"
            conf.custom_pipeline = "hy3dpaint/hunyuanpaintpbr"
            self.paint = Hunyuan3DPaintPipeline(conf)

            print("Pipelines loaded and warm.")
        except Exception as e:
            traceback.print_exc()
            self.load_error = f"pipeline load failed: {e}"

    @modal.method()
    def generate(self, job_id: str, image_url: str | None = None) -> dict:
        started = time.time()
        sb = _supabase()

        job = _fetch_job(sb, job_id)
        if not job:
            print(f"job {job_id} not found — nothing to do")
            return {"status": "failed", "error_code": "internal"}

        user_id = job["user_id"]
        artifact_id = job["artifact_id"]

        if self.load_error:
            print(self.load_error)
            return _finish_job(sb, job_id, user_id, "internal")

        try:
            sb.table("model_jobs").update(
                {"status": "processing", "started_at": _now()}
            ).eq("id", job_id).execute()
        except Exception:
            traceback.print_exc()

        try:
            image_bytes = _download_image(sb, job, image_url)
        except Exception as e:
            print(f"download failed: {e}")
            return _finish_job(sb, job_id, user_id, "internal")

        if len(image_bytes) > MAX_IMAGE_BYTES:
            return _finish_job(sb, job_id, user_id, "internal")

        try:
            glb_bytes = self._run_pipeline(image_bytes)
        except _NoSubject:
            return _finish_job(sb, job_id, user_id, "no_subject")
        except Exception as e:
            traceback.print_exc()
            code = "gpu_oom" if "out of memory" in str(e).lower() else "internal"
            return _finish_job(sb, job_id, user_id, code)

        # `{user_id}/...` is required by the models bucket RLS policy — an
        # object written anywhere else is invisible to the user who owns it.
        storage_path = f"{user_id}/{artifact_id}.glb"
        output_path = f"models/{storage_path}"

        try:
            sb.storage.from_("models").upload(
                path=storage_path,
                file=glb_bytes,
                file_options={
                    "content-type": "model/gltf-binary",
                    # Idempotent on retry: the path is derived from the
                    # artifact, so a re-run overwrites rather than 409s.
                    "upsert": "true",
                },
            )
        except Exception as e:
            print(f"upload failed: {e}")
            traceback.print_exc()
            return _finish_job(sb, job_id, user_id, "internal")

        elapsed = round(time.time() - started, 2)

        try:
            sb.table("model_jobs").update(
                {
                    "status": "succeeded",
                    "output_path": output_path,
                    "finished_at": _now(),
                    "gpu_seconds": elapsed,
                }
            ).eq("id", job_id).execute()
        except Exception:
            traceback.print_exc()

        # The folder reads `artifacts.model_path` on a cold start, when the
        # in-memory job id from this session is gone; without this the model
        # only ever appears to the session that submitted it.
        if artifact_id:
            try:
                sb.table("artifacts").update({"model_path": output_path}).eq(
                    "id", artifact_id
                ).execute()
            except Exception:
                traceback.print_exc()

        print(f"job {job_id} succeeded in {elapsed}s -> {output_path}")
        return {"status": "succeeded", "output_path": output_path, "gpu_seconds": elapsed}

    def _run_pipeline(self, image_bytes: bytes) -> bytes:
        """rembg → crop → shape → paint, in a temp dir of its own.

        The temp dir replaces the old fixed `assets/raw_input.jpg` /
        `demo_textured.glb` paths, which two concurrent jobs in one container
        would clobber.
        """
        import tempfile

        from PIL import Image
        from rembg import remove

        with tempfile.TemporaryDirectory() as work:
            processed = os.path.join(work, "processed.png")
            shape_path = os.path.join(work, "shape.glb")
            out_path = os.path.join(work, "textured.glb")

            source = Image.open(io.BytesIO(image_bytes)).convert("RGB")
            cut = remove(source, session=self.rembg_session)

            # Cropping to the subject's bounding box is what removes the
            # floor/desk shadow and with it the flat-base artifact.
            bbox = cut.getbbox()
            if bbox is None:
                raise _NoSubject()
            cut = cut.crop(bbox)
            cut.save(processed)

            mesh = self.shape(image=cut.convert("RGBA"))[0]
            mesh.export(shape_path)

            self.paint(
                mesh_path=shape_path,
                image_path=processed,
                output_mesh_path=out_path,
            )

            if not os.path.exists(out_path):
                raise RuntimeError("paint pipeline produced no output mesh")

            with open(out_path, "rb") as f:
                return f.read()


class _NoSubject(Exception):
    """rembg found nothing to cut out — a blank wall, or a photo too far back."""


# ---------------------------------------------------------------------------
# Web endpoints
# ---------------------------------------------------------------------------

@app.function(image=image, secrets=[modal.Secret.from_name("supabase-service")])
@modal.fastapi_endpoint(method="POST", requires_proxy_auth=True)
def submit(payload: dict):
    """Queue a job. Returns immediately with the Modal call id.

    Body: {"job_id": "<uuid>", "image_url": "<signed url>", "input_path": "..."}
    """
    from fastapi.responses import JSONResponse

    job_id = (payload or {}).get("job_id")
    if not job_id:
        return JSONResponse({"error": "job_id is required"}, status_code=400)

    call = Generator().generate.spawn(job_id, (payload or {}).get("image_url"))
    print(f"spawned {call.object_id} for job {job_id}")
    return {"call_id": call.object_id}


@app.function(image=image)
@modal.fastapi_endpoint(method="GET", requires_proxy_auth=True)
def status(call_id: str):
    """Non-blocking poll, for reconciling a job whose push never landed."""
    fc = modal.FunctionCall.from_id(call_id)
    try:
        return {"status": "finished", "result": fc.get(timeout=0)}
    except TimeoutError:
        return {"status": "processing"}
