import re
import requests
from flask import Blueprint, request, jsonify
from supabase import create_client, Client, ClientOptions

from config import Config, require_modal_keys
from ingestion.supabase_admin import get_admin_client

models_bp = Blueprint("models", __name__, url_prefix="/api/models")

@models_bp.route("/generate", methods=["POST"])
def generate_model():
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        return jsonify({"error": "unauthorized"}), 401

    jwt = auth_header.replace("Bearer ", "")
    user_client: Client = create_client(
        Config.SUPABASE_URL,
        Config.SUPABASE_ANON_KEY,
        options=ClientOptions(headers={"Authorization": f"Bearer {jwt}"})
    )
    
    try:
        user_resp = user_client.auth.get_user(jwt)
        user = user_resp.user
    except Exception:
        return jsonify({"error": "unauthorized"}), 401

    if not user:
        return jsonify({"error": "unauthorized"}), 401
    
    data = request.get_json() or {}
    artifact_id = data.get("artifact_id")
    image_path = data.get("image_path")
    image_sha256 = data.get("image_sha256")

    if not image_path or not image_path.startswith(f"captures/{user.id}/"):
        return jsonify({"error": "forbidden_path"}), 403

    if not image_sha256 or not re.match(r"^[a-f0-9]{64}$", image_sha256):
        return jsonify({"error": "bad_request"}), 400

    admin = get_admin_client()

    # --- check rate limit ---
    res_rl = admin.rpc("check_rate_limit", {
        "p_user": user.id,
        "p_action": "generate_3d",
        "p_max": 20,
        "p_window": "1 day" 
    }).execute()
    if not res_rl.data:
        return jsonify({"error": "rate_limit_exceeded"}), 429

    # --- quota (atomic) ---
    res = admin.rpc("consume_model_credit", {"p_user": user.id}).execute()
    if not res.data:
        return jsonify({"error": "quota_exceeded"}), 429

    # --- dedupe ---
    hit = admin.table("model_jobs").select("output_path").eq("input_sha256", image_sha256).eq("status", "succeeded").limit(1).execute()
    if hit.data:
        admin.rpc("refund_model_credit", {"p_user": user.id}).execute()
        cached_output = hit.data[0]["output_path"]
        admin.table("artifacts").update({"model_path": cached_output}).eq("id", artifact_id).execute()
        return jsonify({"cached": True, "output_path": cached_output}), 200

    # --- create the job ---
    job_res = admin.table("model_jobs").insert({
        "user_id": user.id,
        "artifact_id": artifact_id,
        "input_path": image_path,
        "input_sha256": image_sha256,
        "status": "queued"
    }).execute()
    
    if not job_res.data:
        admin.rpc("refund_model_credit", {"p_user": user.id}).execute()
        return jsonify({"error": "internal_error"}), 500

    job_id = job_res.data[0]["id"]

    # --- hand off to Modal ---
    storage_path = image_path.replace("captures/", "", 1)
    
    try:
        signed = admin.storage.from_("captures").create_signed_url(storage_path, 600)
    except Exception:
        admin.rpc("refund_model_credit", {"p_user": user.id}).execute()
        return jsonify({"error": "image_not_found"}), 400

    signed_url = signed if isinstance(signed, str) else signed.get('signedURL', signed.get('signedUrl'))
    if not signed_url:
        admin.rpc("refund_model_credit", {"p_user": user.id}).execute()
        admin.table("model_jobs").update({"status": "failed", "error_code": "sign_failed"}).eq("id", job_id).execute()
        return jsonify({"error": "upstream_unavailable"}), 503

    modal_key, modal_secret, modal_submit_url = require_modal_keys()

    try:
        modal_res = requests.post(
            modal_submit_url,
            json={"job_id": job_id, "image_url": signed_url, "input_path": image_path},
            headers={
                "Authorization": f"Bearer {modal_secret}",
                "Modal-Key": modal_key,
                "Modal-Secret": modal_secret
            },
            timeout=10
        )
        modal_res.raise_for_status()
    except requests.exceptions.HTTPError as e:
        admin.table("model_jobs").update({"status": "failed", "error_code": f"http_{e.response.status_code}"}).eq("id", job_id).execute()
        admin.rpc("refund_model_credit", {"p_user": user.id}).execute()
        return jsonify({"error": "upstream_error", "details": e.response.text}), e.response.status_code
    except Exception:
        admin.table("model_jobs").update({"status": "failed", "error_code": "submit_failed"}).eq("id", job_id).execute()
        admin.rpc("refund_model_credit", {"p_user": user.id}).execute()
        return jsonify({"error": "upstream_unavailable"}), 503

    call_id = modal_res.json().get("call_id")
    
    admin.table("model_jobs").update({
        "modal_call_id": call_id,
        "status": "processing"
    }).eq("id", job_id).execute()

    return jsonify({"job_id": job_id}), 200
