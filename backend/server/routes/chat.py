"""Feature 2 from docs/backend/08 — grounded place chat.

Grounding in the location's own blurb/category, plus the explicit
instruction never to invent opening hours or prices, is what keeps this from
being the most likely way the app strands a real traveller at a closed gate.
"""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from data.locations_repo import get_location
from llm import chat, LLMError
from rate_limit import authenticate_and_rate_limit

chat_bp = Blueprint("chat", __name__)

MAX_QUESTION_LEN = 500
MAX_HISTORY_MESSAGES = 6


@chat_bp.post("/api/chat")
def place_chat():
    user, err = authenticate_and_rate_limit("place_chat", max_requests=60, window="1 hour")
    if err:
        return err

    body = request.get_json(silent=True) or {}

    location_id = body.get("location_id")
    question = str(body.get("question") or "").strip()[:MAX_QUESTION_LEN]
    history = body.get("history") or []

    if not location_id or not question:
        return jsonify({"error": "bad_request", "message": "location_id and question are required"}), 400

    location = get_location(location_id)
    if location is None:
        return jsonify({"error": "location_not_found"}), 404

    # Keep only well-formed {role, content} pairs from the tail of history —
    # never trust the shape of client-supplied JSON beyond what we need.
    trimmed_history = [
        {"role": m["role"], "content": str(m["content"])[:MAX_QUESTION_LEN]}
        for m in history[-MAX_HISTORY_MESSAGES:]
        if isinstance(m, dict) and m.get("role") in ("user", "assistant") and m.get("content")
    ]

    system_prompt = (
        "You are a knowledgeable guide to Algerian heritage. Be concise — "
        "2 to 4 sentences. If you are unsure, say so plainly. Never invent "
        "opening hours, ticket prices, or transport details — if asked, say "
        "that detail isn't something you can confirm and suggest checking "
        "locally.\n\n"
        f"Current location: {location['name']} ({location['category']}, "
        f"{location['region']}). {location['blurb']}"
    )

    messages = [{"role": "system", "content": system_prompt}, *trimmed_history, {"role": "user", "content": question}]

    try:
        answer = chat(messages, max_tokens=300, temperature=0.5)
    except LLMError as e:
        return jsonify({"error": "llm_unavailable", "message": str(e)}), 503

    return jsonify({"answer": answer})
