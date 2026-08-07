"""Pure geometry helpers shared by every location data source."""
from __future__ import annotations

import math
import requests


# The demo OSRM server is best-effort and occasionally slow. Ordering has a
# perfectly good haversine fallback, so waiting 10 s for road times buys
# nothing a user would notice — it just delays the whole route by that much.
OSRM_TIMEOUT_S = 6


def get_travel_time_matrix(coords: list[tuple[float, float]]) -> list[list[float]] | None:
    """Fetch a travel time matrix (in seconds) from public OSRM.
    coords is a list of (lat, lng) tuples.
    Returns a 2D list where matrix[i][j] is the time from coords[i] to coords[j].
    Returns None on failure.
    """
    if not coords or len(coords) < 2:
        return None

    # OSRM expects longitude,latitude
    coord_strs = [f"{lng},{lat}" for lat, lng in coords]
    url = f"http://router.project-osrm.org/table/v1/driving/{';'.join(coord_strs)}"

    try:
        resp = requests.get(url, timeout=OSRM_TIMEOUT_S)
        resp.raise_for_status()
        data = resp.json()
        if data.get("code") == "Ok" and "durations" in data:
            return data["durations"]
    except Exception as e:
        import logging
        logging.warning(f"OSRM matrix failed: {e}")
        
    return None

def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance in km. Matches the semantics `latlong2`'s
    `Distance()` uses on the Flutter side — see docs/backend/03, which calls
    out that both sides must agree on this. PostGIS's `ST_Distance` on a
    spheroid (used server-side by `nearby_locations`) differs from this by a
    fraction of a percent — close enough at these scales, per the same doc."""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))
