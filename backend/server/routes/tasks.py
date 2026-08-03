"""Feature 3 from docs/backend/08 — per-location task generation.

The safety instruction below isn't boilerplate: a model asked for "creative
challenges" at, say, a 175m suspension bridge will cheerfully suggest
something that gets someone hurt. Constrain it, then validate the shape
server-side before it ever reaches the app.
"""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from data.locations_repo import get_location
from json_utils import extract_json
from llm import chat, LLMError
from rate_limit import authenticate_and_rate_limit

tasks_bp = Blueprint("tasks", __name__)

ALLOWED_TASK_TYPES = {"mascot", "video", "scan", "photo"}
MIN_POINTS, MAX_POINTS = 10, 100


@tasks_bp.post("/api/tasks/generate")
def generate_task():
    user, err = authenticate_and_rate_limit("generate_task", max_requests=50, window="1 hour")
    if err:
        return err

    body = request.get_json(silent=True) or {}
    location_id = body.get("location_id")

    if not location_id:
        return jsonify({"error": "bad_request", "message": "location_id is required"}), 400

    location = get_location(location_id)
    if location is None:
        return jsonify({"error": "location_not_found"}), 404

    messages = [
        {
            "role": "system",
            "content": (
                "Generate one photo/video/scan challenge for a traveller at "
                "the given location. It must be doable in under 10 minutes, "
                "on foot, with a phone. Do not suggest entering restricted "
                "areas, climbing anything, trespassing, or any other unsafe "
                "act. Reply with a single JSON object shaped exactly like: "
                '{"type": "mascot|video|scan|photo", "label": "...", '
                '"points": 20}. No prose outside the JSON.'
            ),
        },
        {
            "role": "user",
            "content": (
                f"{location['name']} ({location['category']}, {location['region']}). "
                f"{location['blurb']}"
            ),
        },
    ]

    try:
        raw = chat(messages, json_mode=True, max_tokens=300, temperature=0.8)
        parsed = extract_json(raw)
    except LLMError as e:
        return jsonify({"error": "llm_unavailable", "message": str(e)}), 503
    except ValueError as e:
        return jsonify({"error": "llm_bad_output", "message": str(e)}), 502

    task_type = parsed.get("type")
    label = str(parsed.get("label") or "").strip()[:200]
    points = parsed.get("points")

    if task_type not in ALLOWED_TASK_TYPES or not label:
        return jsonify({"error": "llm_bad_output", "message": "Generated task failed validation"}), 502

    try:
        points = max(MIN_POINTS, min(int(points), MAX_POINTS))
    except (TypeError, ValueError):
        points = 30

    return jsonify({"type": task_type, "label": label, "points": points})
