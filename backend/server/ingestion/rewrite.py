"""LLM-powered blurb rewrite and translation for ingested POIs (docs/backend/08, 12).

Wikipedia extracts are encyclopedic in tone and often too long for app cards.
This module rewrites them into concise, editorial-style blurbs and optionally
translates them into the project's supported locales (fr, ar).

Usage:
  from ingestion.rewrite import rewrite_blurb, translate_blurbs

Both functions degrade silently on LLM failure — the caller should treat
a missing return value as "use the raw blurb" rather than erroring out.

Cost note: called per-POI at ingestion time, not per-request. The tile cache
(poi_tiles) ensures each POI is only processed once per cache TTL (60 days),
so the LLM cost is amortised. A cold tile of 20 POIs = 20 rewrite calls.
At Gemini Flash's free tier limits this is negligible, but watch if you
start ingesting thousands of tiles back-to-back.
"""
from __future__ import annotations

import logging
from typing import Optional

logger = logging.getLogger(__name__)

_MAX_INPUT_CHARS = 1200  # clip Wikipedia extract before sending to LLM


def rewrite_blurb(raw_text: str, location_name: str, category: str) -> Optional[str]:
    """Rewrite a Wikipedia extract into a concise, editorial blurb (≤200 chars).

    Returns None if the LLM fails so the caller can fall back to truncation.
    """
    if not raw_text or not raw_text.strip():
        return None

    clipped = raw_text[:_MAX_INPUT_CHARS]

    try:
        from llm import chat
        messages = [
            {
                "role": "system",
                "content": (
                    "You are writing concise captions for a travel app. "
                    "Rewrite the following Wikipedia text as a single, vivid, "
                    "editorial sentence (max 200 characters). "
                    "Keep proper nouns and dates. Omit administrative detail. "
                    "Write directly — no 'It is…' or 'This is…' opener. "
                    "Reply with ONLY the rewritten sentence, nothing else."
                ),
            },
            {
                "role": "user",
                "content": (
                    f"Location: {location_name} ({category})\n"
                    f"Wikipedia extract:\n{clipped}"
                ),
            },
        ]
        result = chat(messages, json_mode=False, max_tokens=200, temperature=0.4)
        result = result.strip()
        # Sanity: must be a non-trivial length (at least 25 chars) and not too long
        if result and 25 <= len(result) <= 300:
            return result[:250]  # cap just in case
        return None
    except Exception as e:
        logger.warning("Blurb rewrite failed for %s: %s", location_name, e)
        return None


def translate_blurbs(
    en_blurb: str,
    location_name: str,
) -> dict[str, str]:
    """Translate a blurb into French (fr) and Arabic (ar).

    Returns a dict with keys 'fr' and 'ar'. Missing translations are
    omitted from the dict rather than returned as None — call sites should
    check key presence.

    Proper nouns (place names in French/Arabic contexts) are a known failure
    mode for machine translation; Arabic especially benefits from human review
    before publication. These are stored as a starting point, not as final copy.
    """
    results: dict[str, str] = {}
    if not en_blurb or not en_blurb.strip():
        return results

    target_langs = {"fr": "French", "ar": "Modern Standard Arabic"}
    for code, lang_name in target_langs.items():
        try:
            from llm import chat
            messages = [
                {
                    "role": "system",
                    "content": (
                        f"Translate the following travel app caption into {lang_name}. "
                        "Keep proper nouns, place names, and dates as-is. "
                        "Reply with ONLY the translated text, nothing else."
                    ),
                },
                {
                    "role": "user",
                    "content": f"Location: {location_name}\n{en_blurb}",
                },
            ]
            result = chat(messages, json_mode=False, max_tokens=200, temperature=0.3)
            result = result.strip()
            if result and len(result) > 15:
                results[code] = result[:300]
        except Exception as e:
            logger.warning("Translation to %s failed for %s: %s", code, location_name, e)

    return results
