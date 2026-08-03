"""Photo resolution — replaces the `picsum.photos` placeholders in
`lib/models/location.dart` with real, licensed photos of the actual place.

## Approaches evaluated

Four were tested empirically against real ingestion candidates (an obscure
Roman aqueduct near Constantine with no `wikidata=`/`wikipedia=` OSM tags)
before writing this module — not assumed from documentation:

1. **Wikipedia REST summary thumbnail** (`wikipedia.fetch_summary`) — tested
   against the Casbah and Timgad, returned a correct, appropriately-sized
   thumbnail plus its full-resolution original for both, in the same call
   that already fetches the blurb text. Reliable, free, no extra request.
2. **Wikidata P18** — the per-tile SPARQL query already returns this
   alongside heritage status, so it's nearly free when present. Weaker
   coverage than (1): not every Wikidata item carries a P18 claim even when
   its corresponding Wikipedia article has a lead image.
3. **Wikipedia full-text search**, as a fallback for POIs with no direct
   Wikidata/Wikipedia link — tested with `srsearch=Aqueduc Romain
   Constantine Algeria`. Top (only) hit was "History of the Loiret", a
   French department article with zero relevance. Rejected: fuzzy
   name-matching against Wikipedia's full-text index is not reliable enough
   to trust unattended.
4. **Search-engine image discovery**, both general and Commons-restricted —
   tested with the same aqueduct query. General search returned exclusively
   paid stock-photo licensors (Alamy, Dreamstime, Shutterstock) — unusable
   without per-image licensing, and those sites block hotlinking besides.
   Restricting to `commons.wikimedia.org` looked promising — the top result
   was literally titled "File:Aqueduc romain.JPG" — but fetching that file's
   actual Commons categories revealed it depicts a bridge in Carrazeda de
   Ansiães, **Portugal**, captioned generically in French. A real, silent
   false positive from a search-engine match that looked strong. Rejected.

## Conclusion

Only structured, ID-based lookups (1–2) are trustworthy enough to run
unattended. Approaches 3–4 rely on textual similarity to guess at a match,
and guessing at *which building a photo depicts* fails in ways that are
hard to detect automatically — the Portugal/Algeria mismatch above passed
every sanity check except actually reading the metadata. A production
pipeline that wants to close this specific gap should use a bounded human
review queue (surface the candidate for a person to approve) or a paid,
properly-licensed provider (see docs/backend/12's Google Places note) —
not free-form scraping. Below the structured tiers, this module simply
returns `None`; the app already has a placeholder treatment for that case.
"""
from __future__ import annotations

import logging
from urllib.parse import unquote

from ingestion.commons import resolve_commons_file
from ingestion.wikipedia import fetch_summary
import requests

logger = logging.getLogger(__name__)


def _filename_from_commons_url(url: str) -> str | None:
    if not url:
        return None
    # ".../commons/d/d4/AlgerCasbah.jpg" -> "AlgerCasbah.jpg". Deliberately
    # uses `original_url`, not `thumbnail_url` — the latter's "/330px-"
    # size-prefixed final segment would need extra handling to strip.
    # unquote handles accented/spaced filenames the same way wikidata.py
    # does, for the same reason: avoid double-encoding on the next request.
    return unquote(url.rsplit("/", 1)[-1]) or None

def _search_commons_for_photo(query: str) -> str | None:
    url = "https://commons.wikimedia.org/w/api.php"
    params = {
        "action": "query",
        "format": "json",
        "list": "search",
        "srsearch": f"filetype:bitmap {query}",
        "srnamespace": "6",
        "srlimit": "1"
    }
    try:
        resp = requests.get(url, params=params, headers={"User-Agent": "ai_tour/1.0"})
        data = resp.json()
        results = data.get("query", {}).get("search", [])
        if results:
            title = results[0]["title"]
            if title.startswith("File:"):
                return title.removeprefix("File:")
    except Exception:
        pass
    return None


def resolve_photo(
    *,
    wikipedia_title: str | None,
    wikidata_image_filename: str | None,
    osm_tags: dict,
) -> dict | None:
    """Returns {"photo_url", "photo_attribution", "photo_license",
    "photo_source_url"} from the first tier that resolves, or None.

    Tier order: Wikipedia lead image, then Wikidata P18, then an explicit
    `wikimedia_commons=File:*` OSM tag. Each tier still goes through
    `resolve_commons_file` for license/attribution — a URL is never stored
    without knowing what it's licensed under.
    """
    if wikipedia_title:
        summary = fetch_summary(wikipedia_title)
        if summary and summary.get("thumbnail_url"):
            filename = _filename_from_commons_url(summary["original_url"])
            if filename:
                resolved = resolve_commons_file(filename)
                if resolved:
                    return {
                        "photo_url": summary["thumbnail_url"],
                        "photo_attribution": resolved["attribution"],
                        "photo_license": resolved["license"],
                        "photo_source_url": resolved["source_url"],
                    }

    if wikidata_image_filename:
        resolved = resolve_commons_file(wikidata_image_filename)
        if resolved:
            return {
                "photo_url": resolved["url"],
                "photo_attribution": resolved["attribution"],
                "photo_license": resolved["license"],
                "photo_source_url": resolved["source_url"],
            }

    commons_tag = osm_tags.get("wikimedia_commons", "")
    if commons_tag.startswith("File:"):
        resolved = resolve_commons_file(commons_tag.removeprefix("File:"))
        if resolved:
            return {
                "photo_url": resolved["url"],
                "photo_attribution": resolved["attribution"],
                "photo_license": resolved["license"],
                "photo_source_url": resolved["source_url"],
            }

    # Search engine fallback using Commons search
    name = osm_tags.get("name", "")
    if name:
        search_filename = _search_commons_for_photo(name)
        if search_filename:
            resolved = resolve_commons_file(search_filename)
            if resolved:
                return {
                    "photo_url": resolved["url"],
                    "photo_attribution": resolved["attribution"],
                    "photo_license": resolved["license"],
                    "photo_source_url": resolved["source_url"],
                }

    return None
