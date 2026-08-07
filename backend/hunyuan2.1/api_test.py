"""End-to-end check of the async 3D pipeline, from the server's side of it.

Unlike the old version this does not upload an image to Modal directly —
there is no synchronous endpoint any more. It exercises the same path the
Flutter app does: create a real `model_jobs` row, POST it to Modal's
proxy-authed `/submit`, then watch the row until the worker patches it.

    python api_test.py                # uses ../../test.jpg
    python api_test.py <image.jpg>

Needs backend/.env (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, MODAL_*).
"""

import hashlib
import os
import sys
import time
import uuid
from pathlib import Path

import requests
from dotenv import load_dotenv
from supabase import create_client

BACKEND_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BACKEND_DIR / ".env")

SUPABASE_URL = os.environ["SUPABASE_URL"]
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
MODAL_SUBMIT_URL = os.environ["MODAL_SUBMIT_URL"]
MODAL_KEY = os.environ["MODAL_PROXY_KEY"]
MODAL_SECRET = os.environ["MODAL_PROXY_SECRET"]

image_path = Path(sys.argv[1]) if len(sys.argv) > 1 else BACKEND_DIR.parent / "test.jpg"
if not image_path.exists():
    sys.exit(f"No such image: {image_path}")

sb = create_client(SUPABASE_URL, SERVICE_KEY)

# Any real user works — the job row just needs an owner whose credits and
# storage prefix exist.
profiles = sb.table("profiles").select("id").limit(1).execute()
if not profiles.data:
    sys.exit("No profiles rows — sign in from the app once first.")
user_id = profiles.data[0]["id"]

artifact_id = str(uuid.uuid4())
image_bytes = image_path.read_bytes()
sha = hashlib.sha256(image_bytes).hexdigest()
storage_path = f"{user_id}/{artifact_id}.jpg"

print(f"user={user_id}\nartifact={artifact_id}\nimage={image_path} ({len(image_bytes):,} bytes)")

sb.storage.from_("captures").upload(
    path=storage_path,
    file=image_bytes,
    file_options={"content-type": "image/jpeg", "upsert": "true"},
)

sb.table("artifacts").insert({
    "id": artifact_id,
    "user_id": user_id,
    "kind": "model",
    "title": "api_test",
    "image_path": f"captures/{storage_path}",
    "local_id": artifact_id,
}).execute()

job_id = sb.table("model_jobs").insert({
    "user_id": user_id,
    "artifact_id": artifact_id,
    "input_path": f"captures/{storage_path}",
    "input_sha256": sha,
    "status": "queued",
}).execute().data[0]["id"]
print(f"job={job_id}")

signed = sb.storage.from_("captures").create_signed_url(storage_path, 600)
signed_url = signed if isinstance(signed, str) else signed.get("signedURL") or signed.get("signedUrl")

resp = requests.post(
    MODAL_SUBMIT_URL,
    json={"job_id": job_id, "image_url": signed_url, "input_path": f"captures/{storage_path}"},
    headers={"Modal-Key": MODAL_KEY, "Modal-Secret": MODAL_SECRET},
    timeout=30,
)
print(f"submit -> {resp.status_code} {resp.text}")
resp.raise_for_status()

print("Waiting for the worker to patch the job (Ctrl-C to stop)...")
last = None
started = time.time()
while time.time() - started < 1800:
    row = sb.table("model_jobs").select(
        "status,error_code,output_path,gpu_seconds"
    ).eq("id", job_id).execute().data[0]
    if row != last:
        print(f"  [{int(time.time() - started):>4}s] {row}")
        last = row
    if row["status"] in ("succeeded", "failed", "cancelled"):
        break
    time.sleep(5)

if last and last.get("output_path"):
    glb = sb.storage.from_("models").download(last["output_path"].removeprefix("models/"))
    out = Path(__file__).parent / "results" / f"{artifact_id}.glb"
    out.parent.mkdir(exist_ok=True)
    out.write_bytes(glb)
    print(f"Downloaded {len(glb):,} bytes -> {out}")
