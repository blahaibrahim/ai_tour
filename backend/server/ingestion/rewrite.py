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


def describe_from_facts(facts: dict) -> Optional[str]:
    """Write a blurb for a POI that has no Wikipedia article, from the OSM
    facts `describe.collect_facts` gathered.

    Distinct from `rewrite_blurb`, which condenses text that already exists.
    Here there is no source text — only a handful of tags — so the prompt is
    explicit that the model may not add anything it wasn't given. Without that
    constraint this is an invitation to invent a founding date and an architect
    for a municipal car park.

    Returns None on any failure or if the result looks unusable, so the caller
    falls back to the deterministic sentence.
    """
    name = facts.get("name") or "this place"
    lines = [f"Name: {name}"]
    if facts.get("kind"):
        lines.append(f"Type: {facts['kind']}")
    if facts.get("embassy"):
        lines.append(f"Role: {facts['embassy']}")
    if facts.get("qualifiers"):
        lines.append("Attributes: " + "; ".join(facts["qualifiers"]))
    if facts.get("place"):
        lines.append(f"City: {facts['place']}")
    if facts.get("street"):
        lines.append(f"Street: {facts['street']}")

    # With only a name and nothing else there is nothing for the model to work
    # from, and asking anyway is how you get invented history.
    if len(lines) < 2:
        return None

    try:
        from llm import chat
        messages = [
            {
                "role": "system",
                "content": (
                    "You write one-sentence captions for a travel app. "
                    "You will be given verified facts about a place. "
                    "Write ONE inviting sentence (max 180 characters) using "
                    "ONLY those facts. Do not invent history, dates, "
                    "architects, significance, or details you were not given. "
                    "Do not repeat the place's name — the app shows it above "
                    "the caption. Do not start with 'It is' or 'This is'. "
                    "Reply with ONLY the sentence."
                ),
            },
            {"role": "user", "content": "\n".join(lines)},
        ]
        result = (chat(messages, json_mode=False, max_tokens=120, temperature=0.5) or "").strip()
    except Exception as e:
        logger.warning("Fact-based description failed for %s: %s", name, e)
        return None

    result = result.strip().strip('"')
    if not (20 <= len(result) <= 260):
        return None
    # A model that starts explaining itself has not written a caption.
    if result.lower().startswith(("i ", "as an", "sorry", "i'm sorry", "unfortunately")):
        return None
    return result


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
