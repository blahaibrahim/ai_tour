"""Interest scoring — deterministic answer to "would a traveller be glad
they went?", computed at ingestion time so route generation
(routes/itinerary.py) can filter and rank without re-deriving this per
request. Weights match the table in docs/backend/12.

Deliberately not an LLM call: this needs to be cheap (runs once per POI per
tile, not per user request), explainable (`score_breakdown` is stored
alongside the total specifically so a bad ranking can be debugged), and
stable (the same inputs always produce the same score, which an LLM
judgement would not guarantee).
"""
from __future__ import annotations

import math
import re

# Names that slipped past Overpass's tag filter (docs/backend/12's query
# already excludes tourism=hotel/information/etc., but a generic-sounding
# *name* on an otherwise-tagged POI — "Souvenir Shop" tagged tourism=gift
# would already be excluded, but a mistagged tourism=attraction named
# "Parking" happens in practice) gets caught here instead.
_GENERIC_NAME_RE = re.compile(
    r"\b(parking|toilets?|wc|restrooms?|souvenir|gift ?shop|snack ?bar|"
    r"car ?park|bus ?stop|entrance|exit|reception|ticket office)\b",
    re.IGNORECASE,
)

_RICHNESS_TAGS = ("website", "opening_hours", "description", "image")


def compute_score(
    *,
    category: str,
    name: str,
    osm_tags: dict,
    wikidata_match: dict | None,
    wikipedia_found: bool,
    pageviews_30d: int | None,
    has_photo: bool,
) -> tuple[float, dict]:
    """Returns (score, breakdown). `breakdown` is stored verbatim in
    `locations.score_breakdown` — see docs/backend/12's "why this needs a
    breakdown column" note."""
    breakdown: dict[str, float] = {}

    if _GENERIC_NAME_RE.search(name):
        breakdown["generic_name_penalty"] = -30
        return -30.0, breakdown

    if wikidata_match:
        if wikidata_match.get("is_unesco"):
            breakdown["unesco_world_heritage"] = 40
        elif wikidata_match.get("has_heritage"):
            breakdown["heritage_designation"] = 25

        if wikidata_match.get("sitelinks", 0) >= 3:
            breakdown["multilingual_coverage"] = 15

    if wikipedia_found:
        breakdown["wikipedia_article"] = 20

    if pageviews_30d and pageviews_30d > 0:
        # log10(30) ≈ 1.5 -> ~6 pts (barely-known); log10(3000) ≈ 3.5 -> ~15
        # pts (regionally known); log10(300000) ≈ 5.5 -> 25 pts, capped
        # (genuinely famous). Log-scaled because raw pageviews span several
        # orders of magnitude between "local landmark" and "UNESCO site
        # everyone's heard of" — a linear scale would make everything below
        # the famous tier score near zero.
        pv_score = min(25.0, math.log10(pageviews_30d) * 6.25)
        breakdown["pageviews"] = round(pv_score, 1)

    if has_photo:
        breakdown["has_photo"] = 10

    if osm_tags.get("wikidata") or osm_tags.get("wikipedia"):
        breakdown["osm_linked_to_wikidata"] = 8

    richness = sum(2 for tag in _RICHNESS_TAGS if osm_tags.get(tag))
    if richness:
        breakdown["osm_tag_richness"] = min(richness, 8)

    if category.strip().lower() not in ("attraction", "point of interest"):
        breakdown["specific_category"] = 10

    if "natural" in osm_tags or "historic" in osm_tags or osm_tags.get("leisure") == "park":
        breakdown["natural_or_historic_baseline"] = 15

    source_count = 1 + (1 if wikidata_match else 0) + (1 if wikipedia_found else 0)
    if source_count >= 2:
        breakdown["corroborated"] = 10

    return sum(breakdown.values()), breakdown
