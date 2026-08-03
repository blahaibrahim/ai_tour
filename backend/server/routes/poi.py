"""Manual trigger for POI ingestion (docs/backend/12).

Deliberately its own endpoint, not a step inside `/api/itinerary`. A cold
tile means several sequential Overpass/Wikidata/Wikipedia/Commons round
trips per POI, with a deliberate delay between each (see ingestion/ingest.py
— added after empirically hitting Overpass's rate limit while testing this).
That can run to tens of seconds per tile; blocking a user's itinerary
request on it would be a bad trade for a one-time cost that should be paid
once per area, not once per request. A background job or scheduled
pre-warm (docs/backend/12's "Pre-warming" section) is the production
answer — this endpoint is the synchronous, explicitly-triggered version of
the same operation, useful for backfilling an area on demand right now.

Requires SUPABASE_SERVICE_ROLE_KEY (see config.require_service_role_key) —
every other route in this app works without it.
"""
from __future__ import annotations

import logging

from flask import Blueprint, jsonify, request
from supabase import create_client, ClientOptions

from config import Config
from ingestion.ingest import ensure_tiles_ingested
from ingestion.supabase_admin import get_admin_client

logger = logging.getLogger(__name__)

poi_bp = Blueprint("poi", __name__)

MAX_RADIUS_KM = 50  # tighter than itinerary's 500km cap — this triggers real ingestion work


@poi_bp.post("/api/poi/ingest")
def ingest_area():
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        return jsonify({"error": "unauthorized"}), 401
        
    jwt = auth_header.replace("Bearer ", "")
    user_client = create_client(
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
    res_rl = admin.rpc("check_rate_limit", {
        "p_user": user.id,
        "p_action": "ingest_poi",
        "p_max": 1000,
        "p_window": "1 day"
    }).execute()
    
    if not res_rl.data:
        return jsonify({"error": "rate_limit_exceeded", "message": "Too many ingest requests today"}), 429

    body = request.get_json(silent=True) or {}

    try:
        lat = float(body["lat"])
        lng = float(body["lng"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "bad_request", "message": "lat and lng are required numbers"}), 400

    if not (-90 <= lat <= 90 and -180 <= lng <= 180):
        return jsonify({"error": "bad_request", "message": "lat/lng out of range"}), 400

    radius_km = min(float(body.get("radius_km", 5)), MAX_RADIUS_KM)

    try:
        summary = ensure_tiles_ingested(lat, lng, radius_km)
    except RuntimeError as e:
        # require_service_role_key() raises this when the key is unset —
        # the one manual-config case worth a distinct status code for.
        return jsonify({"error": "ingestion_unavailable", "message": str(e)}), 503
    except Exception as e:
        logger.exception("Ingestion request failed for (%s, %s, %skm)", lat, lng, radius_km)
        return jsonify({"error": "ingestion_failed", "message": str(e)}), 502

    return jsonify(summary)
