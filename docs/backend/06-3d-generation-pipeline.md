# 06 — 3D Generation Pipeline

> **Status: The target flow below is what now runs.** `backend/hunyuan2.1/api.py`
> is split into `submit` (fast, proxy-authed, `Generator.generate.spawn`),
> the `Generator` GPU worker (pipelines loaded once in `@modal.enter()`,
> per-job temp dirs), and a `status` fallback poll. The worker uploads the
> `.glb` to `models/{user_id}/{artifact_id}.glb` and patches `model_jobs`
> itself; the Flutter client picks that up over Realtime.
>
> Two things had to be true for the client to ever see a result, and neither
> was: Modal had no `/submit` endpoint at all (the Flask route's POST 404'd),
> and `model_jobs` was not in the `supabase_realtime` publication, so even a
> job that finished never reached the app. Both are fixed — the publication in
> `supabase/migrations/20260805201500_realtime_model_jobs.sql`.
>
> **The Flutter half is also complete**, which it was not when this note was
> first written: on-device object labelling gates the capture
> (`services/object_detector.dart`, `google_mlkit_image_labeling`), the image
> is compressed and EXIF-stripped, an optimistic artifact appears in the
> folder immediately (`OptimisticArtifactEvent`), the upload and
> `POST /api/models/generate` call run behind it
> (`repositories/model_repository.dart`), the Realtime subscription in
> `AppBloc._startRealtimeSubscription` moves the artifact to `succeeded` or
> `failed`, and `Flutter3DViewer` renders the cached `.glb`
> (`screens/artifact_viewer/`). The photo-textured `Cube3D` survives only as
> the loading/failure placeholder and as the folder-grid thumbnail
> (`widgets/artifact_cube.dart`) — it is no longer what the viewer shows.
>
> **Still open:** no user-facing retry for a failed job (the folder shows the
> failure, but nothing re-submits), and no thumbnail generation (doc 05).
>
> The sections below describing the old synchronous endpoint are kept as the
> record of why the design changed.

Camera → image → Hunyuan3D 2.1 → `.glb` → the user's folder.

Security hardening of the endpoint is in [07](07-securing-the-3d-endpoint.md).
This document covers the flow and the job model.

## What exists today

`backend/hunyuan2.1/api.py` is a working Modal function: an L4 GPU, a
`from_dockerfile` image built from a CUDA 12.4 base with Hunyuan3D 2.1 cloned
and compiled, three cached volumes, and a FastAPI endpoint that takes a
multipart file and returns GLB bytes.

The pipeline inside is sound: rembg/u2net background removal, crop to the
subject's bounding box (a good call — it's what fixes the flat-base artifact),
then `Hunyuan3DDiTFlowMatchingPipeline` for shape and `Hunyuan3DPaintPipeline`
for texture.

The delivery model around it is what needs work.

### The blocking problem

```python
@modal.fastapi_endpoint(method="POST")
async def generate_3d_api(file: UploadFile = File(...)):
    ...
    subprocess.run(cmd, shell=True, executable="/bin/bash")
    ...
    return Response(content=glb_bytes, media_type="model/gltf-binary")
```

A shape + paint pass on an L4 takes minutes, and the current code reloads both
pipelines from disk on every call, adding more. Modal's web endpoints are not
designed to hold a request open that long — the platform expects a response to
begin well before the multi-minute mark. Check the current limit in Modal's
docs, but assume the synchronous shape doesn't survive contact with a real
model run.

Even if it did, this is wrong for a phone. A mobile HTTP client holding a
connection open for five minutes across a cell handover, screen lock, and app
backgrounding will fail, and the user has no way to know whether their GPU
minutes were spent. `api_test.py` works because it's a desktop script on
Wi-Fi.

**The fix is an async job model**, which the rest of this document describes.

### Other issues in the current function

| Issue | Line | Effect |
| --- | --- | --- |
| Pipelines re-instantiated per request | `custom_pipeline.py` heredoc | Model load added to every call — pure wasted GPU seconds |
| `pip install "setuptools<70.0.0"` at request time | `cmd` | Network dependency in the hot path; fails the request if PyPI is slow |
| Fixed paths `assets/raw_input.jpg`, `demo_textured.glb` | 36–37 | Two concurrent inputs in one container clobber each other |
| `subprocess.run` return code ignored | 115 | A crashed pipeline is diagnosed only by a missing file; the traceback is lost |
| No input validation | 30–33 | Any file, any size, any content |
| `timeout=3600` | 21 | One hung request can hold the GPU for an hour |
| `max_containers=1` | 22 | All users serialize behind one GPU |
| Error body is plain text | 118 | Client can't distinguish "bad photo" from "GPU OOM" |

The heredoc is not a shell-injection risk as written — no user input reaches
the command string. Keep it that way: never interpolate `file.filename` or any
other request field into `cmd`.

## Target flow

```
┌─ App ────────────────────────────────────────────────────────────┐
│ 1. Camera / AR snapshot                                          │
│ 2. Compress, strip EXIF, sha256                                  │
│ 3. Insert artifact + model_job locally  (status: queued)         │
│ 4. Show it in the folder immediately, marked "Generating…"       │
└────────────────────────┬─────────────────────────────────────────┘
                         │ upload image to captures/{uid}/{id}.jpg
                         ▼
┌─ Edge Function: request-model ───────────────────────────────────┐
│  verify JWT · check credits · check sha256 cache · rate limit    │
│  insert model_jobs row · call Modal /submit · store call_id      │
│  return { job_id }                    ~200 ms, never blocks      │
└────────────────────────┬─────────────────────────────────────────┘
                         ▼
┌─ Modal ──────────────────────────────────────────────────────────┐
│  /submit  → Function.spawn(...) → returns call_id immediately    │
│  worker   → download image → rembg → shape → paint               │
│           → upload .glb to Supabase → PATCH job status           │
└────────────────────────┬─────────────────────────────────────────┘
                         ▼
┌─ App ────────────────────────────────────────────────────────────┐
│ 5. Realtime UPDATE on model_jobs → status succeeded              │
│ 6. Download .glb (cached), render in the viewer                  │
└──────────────────────────────────────────────────────────────────┘
```

The user is never waiting on a socket. Close the app, come back tomorrow — the
job completes and the model appears.

## Modal: submit and poll

Split the single function into a fast web endpoint and a slow GPU worker.

```python
import modal, hashlib, os, tempfile, json

app = modal.App("hunyuan3d-api")

hf_cache    = modal.Volume.from_name("hf-cache")
hy3d_cache  = modal.Volume.from_name("hy3dgen-cache")
u2net_cache = modal.Volume.from_name("u2net-cache", create_if_missing=True)

image = modal.Image.from_dockerfile("Dockerfile").pip_install(
    "fastapi", "python-multipart", "supabase", "pillow"
)


@app.cls(
    image=image,
    gpu="L4",
    timeout=900,                    # 15 min ceiling, not an hour
    scaledown_window=300,           # keep the loaded model warm between jobs
    max_containers=4,
    volumes={
        "/root/.cache/huggingface": hf_cache,
        "/root/.cache/hy3dgen": hy3d_cache,
        "/root/.u2net": u2net_cache,
    },
    secrets=[modal.Secret.from_name("supabase-service")],
)
class Generator:

    @modal.enter()
    def load(self):
        """Runs once per container, not once per request."""
        import sys
        sys.path.insert(0, "/workspace/Hunyuan3D-2.1/hy3dshape")
        sys.path.insert(0, "/workspace/Hunyuan3D-2.1/hy3dpaint")
        from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
        from textureGenPipeline import Hunyuan3DPaintPipeline, Hunyuan3DPaintConfig
        from rembg import new_session

        self.rembg = new_session("u2net")
        self.shape = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
            "tencent/Hunyuan3D-2.1"
        )
        conf = Hunyuan3DPaintConfig(6, 512)
        conf.realesrgan_ckpt_path = "hy3dpaint/ckpt/RealESRGAN_x4plus.pth"
        conf.multiview_cfg_path = "hy3dpaint/cfgs/hunyuan-paint-pbr.yaml"
        conf.custom_pipeline = "hy3dpaint/hunyuanpaintpbr"
        self.paint = Hunyuan3DPaintPipeline(conf)

    @modal.method()
    def generate(self, job_id: str, image_bytes: bytes) -> dict:
        from PIL import Image
        from rembg import remove

        with tempfile.TemporaryDirectory() as work:      # per-request isolation
            src  = os.path.join(work, "input.png")
            mesh_path = os.path.join(work, "shape.glb")
            out  = os.path.join(work, "textured.glb")

            img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
            cut = remove(img, session=self.rembg)
            bbox = cut.getbbox()
            if bbox is None:
                return {"status": "failed", "error_code": "no_subject"}
            cut = cut.crop(bbox)
            cut.save(src)

            mesh = self.shape(image=cut.convert("RGBA"))[0]
            mesh.export(mesh_path)
            self.paint(mesh_path=mesh_path, image_path=src, output_mesh_path=out)

            with open(out, "rb") as f:
                glb = f.read()

        key = self._upload(job_id, glb)        # → Supabase Storage, service role
        self._patch_job(job_id, "succeeded", output_path=key)
        return {"status": "succeeded", "output_path": key}
```

Moving the pipeline construction into `@modal.enter()` is the single biggest
change: with `scaledown_window` keeping a container warm, consecutive jobs skip
the model load entirely. Rewriting `custom_pipeline.py` and shelling out on
every request throws that away.

### The submit endpoint

```python
@app.function(image=image, secrets=[modal.Secret.from_name("modal-shared-secret")])
@modal.fastapi_endpoint(method="POST", requires_proxy_auth=True)
async def submit(payload: dict):
    job_id = payload["job_id"]
    image_bytes = base64.b64decode(payload["image_b64"])

    if len(image_bytes) > 10 * 1024 * 1024:
        return JSONResponse({"error": "too_large"}, status_code=413)

    call = Generator().generate.spawn(job_id, image_bytes)
    return {"call_id": call.object_id}


@app.function(image=image)
@modal.fastapi_endpoint(method="GET", requires_proxy_auth=True)
async def status(call_id: str):
    fc = modal.FunctionCall.from_id(call_id)
    try:
        return {"status": "succeeded", "result": fc.get(timeout=0)}
    except TimeoutError:
        return {"status": "processing"}
```

`spawn` returns immediately with a call id; `FunctionCall.from_id(...).get(timeout=0)`
is a non-blocking poll. That's the documented Modal pattern for work that
outlives a request.

Preferably the worker **pushes** its result to Supabase (as `generate` does
above) rather than relying on anyone polling — then `status` is only a fallback
for reconciling jobs whose push failed.

### Sizing and cost

- **`max_containers`**: 1 means every user queues behind every other user. 4 is
  a reasonable starting ceiling — it bounds worst-case spend while allowing
  some parallelism. Tune against real demand.
- **`timeout`**: 900 s. A job that hasn't finished in 15 minutes is stuck;
  paying for an hour of L4 to find that out is a bad trade.
- **`scaledown_window`**: 300 s trades idle GPU time for avoided model loads.
  If jobs are bursty this wins; if they arrive once an hour it loses. Measure.

## The job record

`model_jobs` ([02](02-cloud-database-schema.md)) is the source of truth.

```
queued ──► processing ──► succeeded
   │            │
   │            └───────► failed ──► (retry, attempts < 3) ──► queued
   └──► cancelled
```

Stuck-job reconciliation, since a Modal container can die without ever
patching the row:

```sql
select cron.schedule('reconcile-stuck-jobs', '*/5 * * * *', $$
  update public.model_jobs
     set status = 'failed', error_code = 'timeout', finished_at = now()
   where status in ('queued','processing')
     and queued_at < now() - interval '20 minutes';
$$);
```

Refund the credit when a job fails for a reason that isn't the user's fault
(`timeout`, `gpu_oom`, `internal`). Do not refund `no_subject` or
`invalid_image` — those consumed real compute and the user can fix the input.

## Deduplication

`input_sha256` on `model_jobs` with a partial index over succeeded rows
([02](02-cloud-database-schema.md)) turns a repeat submission into a metadata
copy:

```typescript
const { data: hit } = await supabase
  .from('model_jobs')
  .select('output_path')
  .eq('input_sha256', sha)
  .eq('status', 'succeeded')
  .limit(1).maybeSingle();

if (hit) {
  // point the new artifact at the existing .glb, charge no credit
  return new Response(JSON.stringify({ job_id: null, output_path: hit.output_path }));
}
```

Two users photographing the same museum placard get one GPU run. Do this
globally rather than per-user — the models are identical, and only the
`artifacts` row is user-scoped.

Note the trade-off: a global hash cache means user B's job can be satisfied by
bytes user A uploaded. Since the output is a mesh derived from the image and
never the image itself, and the storage object is served through the requesting
user's own artifact row, this is acceptable. If that ever feels wrong, scope
the cache per-user and accept the extra GPU time.

## Client-side UX

Generation takes minutes. The interface has to make that feel deliberate rather
than broken.

1. **Optimistic insert.** The artifact appears in the folder the instant the
   photo is taken, with the source photo as its thumbnail and a "Generating…"
   state. `AddCapturedArtifactEvent` (`app_event.dart:190`) already does this
   for photos — extend the same path.
2. **Progress that isn't a lie.** Report the real stages the worker publishes:
   *Uploading → Removing background → Building shape → Painting texture*. The
   existing thinking-screen copy pattern (`app_state.dart:86`) is the right
   register for this.
3. **Leaving is safe.** Say so. "You can close the app — we'll finish this in
   the background."
4. **Notification on completion.** Local notification if the app is
   backgrounded (`flutter_local_notifications`), triggered by the realtime
   event on resume. Push via FCM if you want it to fire while fully closed.
5. **Failure is specific.** `no_subject` → "Couldn't find a clear object —
   try filling more of the frame with it." Not "Generation failed", which is
   what the endpoint returns today.

### Capture guidance

Output quality depends almost entirely on the input photo. Cheap wins:

- Overlay a framing guide and a hint: one object, plain background, even light
- Run a blur check on-device before upload (variance of Laplacian, or just
  reject very low-detail frames) — rejecting a bad photo instantly beats
  spending three GPU minutes to produce a bad mesh
- Rear camera, autofocus locked on the subject

## Model alternatives

Hunyuan3D 2.1 gives the best quality of the open options, at the highest cost.
Worth knowing the trade space:

| Model | Speed | Quality | Licence | Fit |
| --- | --- | --- | --- | --- |
| **Hunyuan3D 2.1** (current) | Minutes | Best — PBR textures | Tencent community licence — **read the commercial terms** | Keep as the quality tier |
| **TRELLIS** (Microsoft) | ~30–60 s | Very good | MIT | Strong alternative; permissive licence |
| **TripoSR** | ~1–3 s | Rough, untextured | MIT | Instant preview tier |
| **InstantMesh** | ~10–30 s | Good | Apache 2.0 | Middle ground |
| **Stable Fast 3D** | ~1 s | Good for the speed | Stability community licence | Fast tier |

A two-tier design is attractive: **TripoSR immediately** for a preview the user
sees in seconds, then **Hunyuan3D** in the background for the keeper. The
perceived latency problem largely disappears.

Check the Hunyuan3D 2.1 licence terms against your intended use before launch.
Tencent's community licences carry conditions (user thresholds, territorial
restrictions) that differ from MIT/Apache. TRELLIS under MIT avoids that
question entirely.

### Background removal upgrades

`u2net` is the default and it's mediocre on fine edges. The code already
comments on this. `isnet-general-use` is a drop-in `new_session()` swap for
better quality; **BiRefNet** is the current state of the art and worth the
extra second. Better matting means a better mesh — this is high-leverage.

## Testing checklist

- [ ] Submit returns in under 500 ms regardless of job length
- [ ] Kill the app immediately after submit → the model still appears later
- [ ] Two identical images → one GPU run, two artifacts
- [ ] Photo of a blank wall → `no_subject`, specific message, no credit charged
- [ ] Worker killed mid-job → reconciler marks it failed within 20 min and refunds
- [ ] 20 MB upload → rejected before it reaches the GPU
- [ ] Concurrent jobs in one container write to separate temp dirs
- [ ] Second job in a warm container skips the model load (check the logs)
- [ ] Generated `.glb` passes `GlbBounds` parsing and renders in the AR session
