/** Pure geometry helpers shared by every location data source. */
import { getLogger } from "../logger";
import { getJson } from "../http";

const logger = getLogger("data.geo");

// The demo OSRM server is best-effort and occasionally slow. Ordering has a
// perfectly good haversine fallback, so waiting 10 s for road times buys
// nothing a user would notice — it just delays the whole route by that much.
export const OSRM_TIMEOUT_S = 6;

interface OsrmTableResponse {
  code?: string;
  durations?: Array<Array<number | null>>;
}

/**
 * Fetch a travel time matrix (in seconds) from public OSRM.
 * `coords` is a list of [lat, lng] pairs.
 * Returns a 2D array where matrix[i][j] is the time from coords[i] to coords[j].
 * Returns null on failure.
 */
export async function getTravelTimeMatrix(
  coords: Array<[number, number]>,
): Promise<Array<Array<number | null>> | null> {
  if (!coords || coords.length < 2) return null;

  // OSRM expects longitude,latitude
  const coordStrs = coords.map(([lat, lng]) => `${lng},${lat}`);
  const url = `http://router.project-osrm.org/table/v1/driving/${coordStrs.join(";")}`;

  try {
    const data = await getJson<OsrmTableResponse>(url, { timeoutMs: OSRM_TIMEOUT_S * 1000 });
    if (data.code === "Ok" && data.durations) {
      return data.durations;
    }
  } catch (error) {
    logger.warning(`OSRM matrix failed: ${error instanceof Error ? error.message : error}`);
  }

  return null;
}

/**
 * Great-circle distance in km. Matches the semantics `latlong2`'s `Distance()`
 * uses on the Flutter side — see docs/backend/03, which calls out that both
 * sides must agree on this. PostGIS's `ST_Distance` on a spheroid (used
 * server-side by `nearby_locations`) differs from this by a fraction of a
 * percent — close enough at these scales, per the same doc.
 */
export function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const r = 6371.0;
  const toRad = (deg: number): number => (deg * Math.PI) / 180;
  const p1 = toRad(lat1);
  const p2 = toRad(lat2);
  const dphi = toRad(lat2 - lat1);
  const dlambda = toRad(lng2 - lng1);
  const a =
    Math.sin(dphi / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dlambda / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(a));
}
