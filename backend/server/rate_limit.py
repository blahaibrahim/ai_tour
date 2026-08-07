import hashlib
import logging
import sys
import threading
import time
from typing import Tuple, Optional, Any

from flask import request, jsonify
from supabase import create_client, ClientOptions

from config import Config
from ingestion.supabase_admin import get_admin_client

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
if not logger.handlers:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter('[%(levelname)s] %(name)s - %(message)s'))
    logger.addHandler(handler)


# Verified-JWT cache.
#
# Every authenticated route paid a `create_client` plus a network round trip to
# GoTrue's /user on *every* request, and the client polls
# /api/itinerary/job/<id> once a second while a route generates — so a single
# route generation spent more wall time re-verifying the same token than the
# work it was polling for. Access tokens are valid for an hour; re-checking one
# every 60 s is the same guarantee at a fraction of the cost, and a revoked
# session still stops working within the window.
_JWT_TTL_S = 60
_jwt_cache: dict[str, tuple[float, Any]] = {}
_jwt_lock = threading.Lock()


def _cached_user(jwt: str) -> Optional[Any]:
    key = hashlib.sha256(jwt.encode()).hexdigest()
    now = time.time()

    with _jwt_lock:
        entry = _jwt_cache.get(key)
        if entry and now - entry[0] < _JWT_TTL_S:
            return entry[1]

    user_client = create_client(
        Config.SUPABASE_URL,
        Config.SUPABASE_ANON_KEY,
        options=ClientOptions(headers={"Authorization": f"Bearer {jwt}"})
    )

    try:
        user = user_client.auth.get_user(jwt).user
    except Exception as e:
        logger.error(f"Failed to get_user with provided JWT. Error: {e}", exc_info=True)
        return None

    if user is None:
        return None

    with _jwt_lock:
        # Expired entries are only ever evicted here, which is fine: the key
        # space is one entry per active session, not per request.
        if len(_jwt_cache) > 512:
            for stale in [k for k, v in _jwt_cache.items() if now - v[0] >= _JWT_TTL_S]:
                _jwt_cache.pop(stale, None)
        _jwt_cache[key] = (now, user)
    return user


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
    user = _cached_user(jwt)

    if not user:
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
