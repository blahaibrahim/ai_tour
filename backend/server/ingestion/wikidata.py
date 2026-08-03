"""Wikidata SPARQL enrichment — the strongest free "is this worth visiting?"
signal available (docs/backend/12). One query per tile returns everything
scoring needs: heritage designation, a Commons image, and the English
Wikipedia article, all in a single round trip rather than one lookup per POI.
"""
from __future__ import annotations

import logging
import re
from urllib.parse import unquote

import requests

from config import Config
from data.geo import haversine_km

logger = logging.getLogger(__name__)

SPARQL_URL = "https://query.wikidata.org/sparql"
TIMEOUT_S = 25

UNESCO_QID = "Q9259"

_QUERY_TEMPLATE = """
SELECT ?item ?itemLabel ?location ?heritage ?image ?article ?sitelinks WHERE {{
  SERVICE wikibase:around {{
    ?item wdt:P625 ?location .
    bd:serviceParam wikibase:center "Point({lng} {lat})"^^geo:wktLiteral .
    bd:serviceParam wikibase:radius "{radius_km}" .
  }}
  ?item wikibase:sitelinks ?sitelinks .
  OPTIONAL {{ ?item wdt:P1435 ?heritage . }}
  OPTIONAL {{ ?item wdt:P18   ?image . }}
  OPTIONAL {{
    ?article schema:about ?item ;
             schema:isPartOf <https://en.wikipedia.org/> .
  }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}
"""

_QID_RE = re.compile(r"Q\d+$")
_POINT_RE = re.compile(r"Point\(([-\d.]+) ([-\d.]+)\)")


def _user_agent() -> str:
    contact = Config.OVERPASS_CONTACT or "no-contact-configured"
    return f"ai_tour_ingestion/1.0 ({contact})"


def _qid_from_uri(uri: str) -> str | None:
    m = _QID_RE.search(uri)
    return m.group(0) if m else None


def _parse_point(wkt: str) -> tuple[float, float] | None:
    m = _POINT_RE.match(wkt)
    if not m:
        return None
    lng, lat = float(m.group(1)), float(m.group(2))
    return lat, lng


def fetch_wikidata_items(lat: float, lng: float, radius_km: float) -> list[dict]:
    """Wikidata items near a point, one row per item with duplicate
    heritage/image/article bindings collapsed. Returns `[]` on failure —
    ingestion proceeds with OSM-only signals rather than blocking on this.
    """
    query = _QUERY_TEMPLATE.format(lat=lat, lng=lng, radius_km=max(radius_km, 0.1))

    try:
        resp = requests.get(
            SPARQL_URL,
            params={"query": query, "format": "json"},
            headers={"User-Agent": _user_agent(), "Accept": "application/sparql-results+json"},
            timeout=TIMEOUT_S,
        )
        resp.raise_for_status()
        bindings = resp.json()["results"]["bindings"]
    except requests.RequestException as e:
        logger.warning("Wikidata SPARQL request failed for (%s, %s): %s", lat, lng, e)
        return []
    except (ValueError, KeyError):
        logger.warning("Wikidata SPARQL returned unexpected shape for (%s, %s)", lat, lng)
        return []

    by_qid: dict[str, dict] = {}
    for row in bindings:
        item_uri = row.get("item", {}).get("value", "")
        qid = _qid_from_uri(item_uri)
        if not qid:
            continue

        entry = by_qid.setdefault(
            qid,
            {
                "qid": qid,
                "name": row.get("itemLabel", {}).get("value") or qid,
                "lat": None,
                "lng": None,
                "is_unesco": False,
                "has_heritage": False,
                "image_filename": None,
                "wikipedia_title": None,
                "sitelinks": int(row.get("sitelinks", {}).get("value", 0)),
            },
        )

        if entry["lat"] is None and "location" in row:
            point = _parse_point(row["location"]["value"])
            if point:
                entry["lat"], entry["lng"] = point

        heritage_uri = row.get("heritage", {}).get("value")
        if heritage_uri:
            entry["has_heritage"] = True
            if _qid_from_uri(heritage_uri) == UNESCO_QID:
                entry["is_unesco"] = True

        if entry["image_filename"] is None and "image" in row:
            # Commons file URIs look like .../Special:FilePath/<name>, with
            # accented/spaced filenames percent-encoded — decode now so a
            # later request doesn't double-encode it into a 404.
            entry["image_filename"] = unquote(row["image"]["value"].rsplit("/", 1)[-1])

        if entry["wikipedia_title"] is None and "article" in row:
            # e.g. https://en.wikipedia.org/wiki/Casbah_of_Algiers
            entry["wikipedia_title"] = unquote(row["article"]["value"].rsplit("/", 1)[-1])

    return [e for e in by_qid.values() if e["lat"] is not None]


def match_nearest(
    poi_lat: float, poi_lng: float, items: list[dict], max_distance_m: float = 75
) -> dict | None:
    """Nearest Wikidata item to an OSM point, within `max_distance_m`. Called
    only when the OSM element has no explicit `wikidata=*` tag — proximity is
    a weaker signal than an explicit tag, so the radius here is deliberately
    tight to avoid pairing a POI with the wrong nearby item."""
    best, best_dist = None, max_distance_m / 1000.0
    for item in items:
        dist_km = haversine_km(poi_lat, poi_lng, item["lat"], item["lng"])
        if dist_km <= best_dist:
            best, best_dist = item, dist_km
    return best
