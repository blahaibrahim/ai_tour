import os
import requests
import time
from supabase import create_client
from dotenv import load_dotenv
import hashlib

load_dotenv("../.env")

# Path to the real test image provided by the user
test_image_path = "../../test.jpg"
with open(test_image_path, "rb") as f:
    test_image_bytes = f.read()

image_hash = hashlib.sha256(test_image_bytes).hexdigest()

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)

print("1. Signing in with test user...")
auth_resp = client.auth.sign_in_with_password({"email": "test@ai-tour.app", "password": "password123"})

user_id = auth_resp.user.id
jwt = auth_resp.session.access_token

print(f"User ID: {user_id}")

print("2. Uploading test image to 'captures' bucket...")
image_path = f"captures/{user_id}/test.jpg"

admin_client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
try:
    admin_client.storage.from_("captures").upload(
        f"{user_id}/test.jpg",
        test_image_bytes,
        file_options={"content-type": "image/jpeg", "upsert": "true"}
    )
except Exception as e:
    print("Warning: Upload might have failed or already exists:", e)


print("3. Creating a dummy artifact...")
artifact_res = client.table("artifacts").insert({
    "user_id": user_id,
    "kind": "model",
    "title": "Test 3D Model",
}).execute()
artifact_id = artifact_res.data[0]["id"]

print("4. Testing /api/models/generate (Async)...")
resp = requests.post(
    "http://127.0.0.1:8000/api/models/generate",
    json={
        "artifact_id": artifact_id,
        "image_path": image_path,
        "image_sha256": image_hash
    },
    headers={
        "Authorization": f"Bearer {jwt}"
    }
)

print(f"Status: {resp.status_code}")
if resp.status_code != 200:
    print(f"Response: {resp.text}")
    exit(1)

data = resp.json()
if data.get("cached"):
    print(f"Reusing cached 3D Model: {data.get('output_path')}")
    exit(0)

job_id = data.get("job_id")
print(f"Job submitted successfully! Job ID: {job_id}")

print("\n5. Polling Supabase for job completion...")
import sys
while True:
    time.sleep(3)
    job_res = admin_client.table("model_jobs").select("status, error_code, output_path").eq("id", job_id).execute()
    if not job_res.data:
        print("Job disappeared from database!")
        break
        
    status = job_res.data[0]["status"]
    err = job_res.data[0].get("error_code")
    out = job_res.data[0].get("output_path")
    
    sys.stdout.write(f"\rCurrent status: {status}")
    sys.stdout.flush()
    
    if status == "succeeded":
        print(f"\nGeneration successful! Output path: {out}")
        # Download the .glb to project root
        try:
            signed = admin_client.storage.from_("models").create_signed_url(out, 300)
            signed_url = signed if isinstance(signed, str) else signed.get("signedURL", signed.get("signedUrl"))
            if signed_url:
                glb_bytes = requests.get(signed_url).content
                out_path = os.path.join(os.path.dirname(__file__), "../../result_from_api.glb")
                with open(out_path, "wb") as f:
                    f.write(glb_bytes)
                print(f"Downloaded .glb to {os.path.abspath(out_path)} ({len(glb_bytes):,} bytes)")
        except Exception as e:
            print(f"Warning: Could not download .glb: {e}")
        break
    elif status == "failed":
        print(f"\nGeneration failed! Error: {err}")
        break
        
print("\nTest completed.")
