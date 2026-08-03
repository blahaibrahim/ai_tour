"""Deterministic tile covering for the POI cache (docs/backend/12).

docs/backend/12 suggests geohash precision 5 or H3 resolution 7 for this.
Both need an extra dependency and, for geohash, a non-trivial neighbour
algorithm to correctly enumerate a covering set. A plain equirectangular
degree grid gives the same operational property that actually matters here
— a deterministic, reusable cache key per patch of ground, so repeated
queries over the same area hit the cache instead of re-fetching — with about
15 lines of code and zero dependencies. Swapping to geohash/H3 later only
touches this file; every caller just consumes `tile_id` strings and
`(lat_min, lat_max, lng_min, lng_max)` bounds.
"""
from __future__ import annotations

import math

# ~0.045 degrees of latitude is ~5 km, matching docs/backend/12's target
# cell size. Longitude cells are the same angular size, so they're narrower
# in km than in latitude the further from the equator — irrelevant here
# since tiles are only ever used as opaque cache keys, never for distance
# math (PostGIS geography handles all real distance calculations).
TILE_SIZE_DEG = 0.045

# Bounds a single ingestion call: a 500 km radius could otherwise expand to
# thousands of tiles, each a real Overpass + Wikidata round trip. Radius
# itself is already capped in routes/poi.py; this is the second, independent
# cap specifically on *new* fetches per call — a warm cache can still answer
# a wide query instantly, this only limits how much *uncached* ground one
# request will pay to fill in. See docs/backend/12's "Pre-warming" note:
# systematic backfill of a wide area is a job for a scheduled task, not a
# side effect of one user's request.
# Started at 9 (a 3x3 grid); cut to 3 after empirically hitting Overpass's
# rate limit (HTTP 429) partway through manual testing of this pipeline —
# each tile costs one Overpass call, one Wikidata call, and several
# Wikipedia/Commons calls, so even a modest tile count adds up fast against
# free public infrastructure with real fair-use limits.
MAX_TILES_PER_INGEST = 3


def _bin(value: float) -> int:
    return math.floor(value / TILE_SIZE_DEG)


def tile_id_for(lat: float, lng: float) -> str:
    return f"{_bin(lat)}_{_bin(lng)}"


def tile_bounds(tile_id: str) -> tuple[float, float, float, float]:
    """Returns (lat_min, lat_max, lng_min, lng_max) for a tile id."""
    lat_bin_s, lng_bin_s = tile_id.split("_")
    lat_bin, lng_bin = int(lat_bin_s), int(lng_bin_s)
    return (
        lat_bin * TILE_SIZE_DEG,
        (lat_bin + 1) * TILE_SIZE_DEG,
        lng_bin * TILE_SIZE_DEG,
        (lng_bin + 1) * TILE_SIZE_DEG,
    )


def covering_tiles(lat: float, lng: float, radius_km: float) -> list[str]:
    """Tile ids whose bounding boxes intersect the query circle, nearest the
    center first (so truncation by MAX_TILES_PER_INGEST drops the tiles
    least likely to matter)."""
    lat_pad_deg = radius_km / 111.0
    # Longitude degrees shrink towards the poles; guard against cos(lat)==0
    # at the poles even though this app's whole coverage area (Algeria) is
    # nowhere near them — cheap insurance against a future caller passing
    # an unexpected latitude.
    cos_lat = max(math.cos(math.radians(lat)), 1e-6)
    lng_pad_deg = radius_km / (111.0 * cos_lat)

    lat_min_bin, lat_max_bin = _bin(lat - lat_pad_deg), _bin(lat + lat_pad_deg)
    lng_min_bin, lng_max_bin = _bin(lng - lng_pad_deg), _bin(lng + lng_pad_deg)

    candidates = []
    for lat_bin in range(lat_min_bin, lat_max_bin + 1):
        for lng_bin in range(lng_min_bin, lng_max_bin + 1):
            tile_lat = (lat_bin + 0.5) * TILE_SIZE_DEG
            tile_lng = (lng_bin + 0.5) * TILE_SIZE_DEG
            d_lat = (tile_lat - lat) * 111.0
            d_lng = (tile_lng - lng) * 111.0 * cos_lat
            dist_km = math.hypot(d_lat, d_lng)
            candidates.append((dist_km, f"{lat_bin}_{lng_bin}"))

    candidates.sort(key=lambda c: c[0])
    return [tile_id for _, tile_id in candidates[:MAX_TILES_PER_INGEST]]
