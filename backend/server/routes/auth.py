import os
from flask import Blueprint, request, jsonify
from supabase import create_client, Client, ClientOptions

from config import Config
from ingestion.supabase_admin import get_admin_client

auth_bp = Blueprint("auth", __name__, url_prefix="/api/auth")

@auth_bp.route("/delete-account", methods=["POST"])
def delete_account():
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

    admin = get_admin_client()

    try:
        # Delete the user's storage objects inside captures/ and models/
        # Supabase Python SDK doesn't natively support recursive deletes for prefixes easily,
        # but we can list and delete.
        for bucket in ["captures", "models", "thumbnails"]:
            # List objects with the user's prefix
            # Note: storage.list() might not be fully recursive if there are sub-subfolders, 
            # but our path structure is strictly {uid}/{id}.jpg
            files = admin.storage.from_(bucket).list(user.id)
            if files:
                file_paths = [f"{user.id}/{f['name']}" for f in files if f['name'] != '.emptyFolderPlaceholder']
                if file_paths:
                    admin.storage.from_(bucket).remove(file_paths)
    except Exception as e:
        print(f"Failed to delete storage objects for user {user.id}: {e}")
        # Proceed with account deletion even if storage fails, 
        # orphan purge cron will catch them.

    try:
        # Deleting the user cascades to public.profiles and related user-scoped tables
        admin.auth.admin.delete_user(user.id)
    except Exception as e:
        print(f"Failed to delete auth user {user.id}: {e}")
        return jsonify({"error": "deletion_failed"}), 500

    return jsonify({}), 204
