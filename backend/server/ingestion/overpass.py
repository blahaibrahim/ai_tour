"""Overpass client — Stage 1 (Fetch) of the route-generation funnel.

docs/backend/12 specifies the query shape: tourism/historic/natural POIs,
explicitly excluding accommodation, information boards, and gift shops,
which dominate an unfiltered feed and are never a stop on a tour.
"""
from __future__ import annotations

import logging

import requests

from config import Config

logger = logging.getLogger(__name__)

OVERPASS_MIRRORS = [
    "https://overpass-api.de/api/interpreter",
    "https://z.overpass-api.de/api/interpreter",
    "https://lz4.overpass-api.de/api/interpreter",
]
TIMEOUT_S = 30

_QUERY_TEMPLATE = """
[out:json][timeout:25];
(
  node["tourism"]({lat_min},{lng_min},{lat_max},{lng_max});
  way ["tourism"]({lat_min},{lng_min},{lat_max},{lng_max});

  node["historic"]({lat_min},{lng_min},{lat_max},{lng_max});
  way ["historic"]({lat_min},{lng_min},{lat_max},{lng_max});

  node["natural"~"^(peak|cave_entrance|arch|spring|beach|bay|cape|cliff|glacier|volcano|water)$"]({lat_min},{lng_min},{lat_max},{lng_max});
  way ["natural"~"^(beach|bay|cape|cliff|glacier|volcano|water)$"]({lat_min},{lng_min},{lat_max},{lng_max});
  way ["leisure"="park"]({lat_min},{lng_min},{lat_max},{lng_max});
  way ["waterway"="waterfall"]({lat_min},{lng_min},{lat_max},{lng_max});
);
out center tags;
"""

_EXCLUDED_TOURISM = {
    "hotel", "hostel", "guest_house", "apartment", "motel", "camp_site",
    "caravan_site", "chalet", "information", "picnic_site",
}


def _user_agent() -> str:
    contact = Config.OVERPASS_CONTACT or "no-contact-configured"
    return f"ai_tour_ingestion/1.0 ({contact})"


def _category_from_tags(tags: dict) -> str | None:
    """Normalizes the several OSM tagging schemes this query touches into
    one display category. Order matters: `historic` is checked first
    because it's the most specific signal for this app's actual subject —
    heritage sites — even when a `tourism` tag is also present."""
    if "historic" in tags:
        return tags["historic"].replace("_", " ").capitalize()
    if tags.get("tourism") and tags["tourism"] not in _EXCLUDED_TOURISM:
        return tags["tourism"].replace("_", " ").capitalize()
    if "natural" in tags:
        return {"peak": "Peak", "cave_entrance": "Cave", "arch": "Natural arch", "spring": "Spring", "beach": "Beach", "bay": "Bay", "cape": "Cape", "cliff": "Cliff", "glacier": "Glacier", "volcano": "Volcano", "water": "Water"}.get(
            tags["natural"], tags["natural"].replace("_", " ").capitalize()
        )
    if tags.get("leisure") == "park":
        return "Park"
    if tags.get("waterway") == "waterfall":
        return "Waterfall"
    return None


def _name_from_tags(tags: dict) -> str | None:
    # English-first since only 'en' translations are populated today
    # (docs/backend/09 covers multilingual content; not wired up yet).
    return tags.get("name:en") or tags.get("int_name") or tags.get("name")


class OverpassError(RuntimeError):
    """Raised when Overpass can't be reached or returns something unusable.

    Deliberately **not** swallowed into an empty list here — that was the
    original design and it produced a real bug during live testing: a 504
    from Overpass (hit for real, mid-ingestion, on a shared public instance)
    resulted in `_ingest_one_tile` finishing with zero POIs and the tile
    getting cached as `fetch_status='ok', poi_count=0` for the normal 60-day
    TTL. That's indistinguishable from "this tile genuinely has nothing in
    it" and silently poisons the cache for two months over a transient
    timeout. Raising here lets `ingestion/ingest.py`'s existing tile-level
    exception handling do the right thing instead — mark the tile `failed`
    with a 1-day retry TTL, which is what already happens for every other
    exception in that path; Overpass failures just weren't reaching it.
    """


def fetch_pois(lat_min: float, lng_min: float, lat_max: float, lng_max: float) -> list[dict]:
    """Raw POIs from Overpass, already filtered to named + categorized —
    the noise Overpass returns alongside real POIs (unnamed benches,
    `tourism=information` signs) is dropped here rather than passed on to
    scoring. Raises `OverpassError` on failure — see that class's docstring
    for why this isn't a quiet `[]` return.
    """
    query = _QUERY_TEMPLATE.format(lat_min=lat_min, lng_min=lng_min, lat_max=lat_max, lng_max=lng_max)

    last_err = None
    elements = []
    
    for url in OVERPASS_MIRRORS:
        try:
            resp = requests.post(
                url,
                data={"data": query},
                headers={"User-Agent": _user_agent()},
                timeout=TIMEOUT_S,
            )
            if resp.status_code == 429:
                last_err = f"429 Too Many Requests from {url}"
                continue
            resp.raise_for_status()
            elements = resp.json().get("elements", [])
            last_err = None
            break
        except requests.RequestException as e:
            last_err = f"Request failed for {url}: {e}"
            continue
        except ValueError as e:
            last_err = f"Non-JSON from {url}: {e}"
            continue

    if last_err is not None:
        raise OverpassError(f"All Overpass mirrors failed. Last error: {last_err}")

    pois = []
    for el in elements:
        tags = el.get("tags", {})
        name = _name_from_tags(tags)
        category = _category_from_tags(tags)
        if not name or not category:
            continue

        if el["type"] == "node":
            poi_lat, poi_lng = el.get("lat"), el.get("lon")
        else:
            center = el.get("center") or {}
            poi_lat, poi_lng = center.get("lat"), center.get("lon")
        if poi_lat is None or poi_lng is None:
            continue

        pois.append(
            {
                "osm_type": el["type"],
                "osm_id": el["id"],
                "name": name,
                "category": category,
                "lat": poi_lat,
                "lng": poi_lng,
                "tags": tags,
                "wikidata_qid": tags.get("wikidata"),
                "wikipedia": tags.get("wikipedia"),  # "en:Casbah of Algiers" form
            }
        )

    return pois
