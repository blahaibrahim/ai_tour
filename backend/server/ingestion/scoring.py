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

# Places whose *name* says they are closed to visitors even when their tags
# don't. "Djenane El Mithak (Résidence d'Etat)" carries no `barrier` and no
# `office=diplomatic`, so nothing else catches it — it reached the offered
# candidate list as an ordinary park. Embassies are normally excluded by tag
# in ingestion/overpass.py; the name is the backstop for the ones tagged
# incompletely.
_CLOSED_TO_VISITORS_RE = re.compile(
    r"(r[ée]sidence\s+d\s*['’]?\s*[ée]tat|ambassade|embassy|"
    r"consulat(e)?|chancellerie)",
    re.IGNORECASE,
)

_RICHNESS_TAGS = ("website", "opening_hours", "description", "image")


def _is_walled_enclosure(osm_tags: dict) -> bool:
    """A walled/fenced enclosure mapped as a park with nothing saying it is
    public — `barrier=wall` + `leisure=park` and no knowledge-base link,
    tourism tag, historic tag or `access`.

    In Algiers this pattern is state residences and private villa grounds:
    "Résidence d'Etat", "Domaine Bensmen", "Villa Montfeld", "Villa Sidi
    Allaoui", and a plant nursery — all of which a naive `leisure=park` rule
    reads as public parks worth 25 points, ahead of actual mosques.

    A **penalty and not an exclusion**, because the signal is ambiguous rather
    than wrong: Dar Aziza, a 16th-century Ottoman palace, carries exactly the
    same tags as Villa Montfeld and nothing in OSM distinguishes them. Scoring
    it down puts it below every properly-tagged landmark while leaving it
    available in a sparse area, which dropping it would not.
    """
    if osm_tags.get("barrier") not in ("wall", "fence"):
        return False
    if osm_tags.get("leisure") != "park":
        return False
    return not (
        osm_tags.get("wikidata")
        or osm_tags.get("wikipedia")
        or osm_tags.get("tourism")
        or osm_tags.get("historic")
        or osm_tags.get("access") in ("yes", "public", "permissive")
    )


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

    if _CLOSED_TO_VISITORS_RE.search(name):
        breakdown["closed_to_visitors"] = -30
        return -30.0, breakdown

    if _is_walled_enclosure(osm_tags):
        breakdown["walled_private_grounds"] = -20

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
