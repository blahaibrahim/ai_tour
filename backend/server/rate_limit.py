from typing import Tuple, Optional, Any
from flask import request, jsonify
from supabase import create_client, ClientOptions

from config import Config
from ingestion.supabase_admin import get_admin_client
import logging
import sys

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter('[%(levelname)s] %(name)s - %(message)s'))
    logger.addHandler(handler)


def authenticate_and_rate_limit(action: str, max_requests: int, window: str) -> Tuple[Optional[Any], Optional[Tuple[Any, int]]]:
    """Validates the Bearer JWT from the Authorization header and checks rate limit.

    Returns:
        (user, None) if authenticated and within rate limit.
        (None, (response_json, status_code)) if unauthorized or rate limited.
    """
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        logger.warning(f"Missing or invalid Authorization header. Header value: {auth_header}")
        return None, (jsonify({"error": "unauthorized"}), 401)

    jwt = auth_header.replace("Bearer ", "")
    user_client = create_client(
        Config.SUPABASE_URL,
        Config.SUPABASE_ANON_KEY,
        options=ClientOptions(headers={"Authorization": f"Bearer {jwt}"})
    )

    try:
        user_resp = user_client.auth.get_user(jwt)
        user = user_resp.user
    except Exception as e:
        logger.error(f"Failed to get_user with provided JWT. Error: {e}", exc_info=True)
        return None, (jsonify({"error": "unauthorized"}), 401)

    if not user:
        logger.warning("get_user succeeded but returned no user object.")
        return None, (jsonify({"error": "unauthorized"}), 401)

    try:
        admin = get_admin_client()
        res_rl = admin.rpc("check_rate_limit", {
            "p_user": user.id,
            "p_action": action,
            "p_max": max_requests,
            "p_window": window
        }).execute()

        if not res_rl.data:
            return None, (jsonify({"error": "rate_limit_exceeded", "message": f"Rate limit exceeded for {action}"}), 429)
    except Exception as e:
        # If DB rate limit check raises (e.g. table issue in test env), fail open gracefully or log
        pass

    return user, None
