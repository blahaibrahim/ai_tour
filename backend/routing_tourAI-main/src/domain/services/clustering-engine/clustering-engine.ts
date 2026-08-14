import type { Cluster } from '../../models/cluster.model.js';
import type { Coordinate } from '../../models/coordinate.model.js';
import type { Poi } from '../../models/poi.model.js';

/**
 * Fixed-radius greedy grouping (Section 5): POIs within the city's
 * configured radius of each other join a cluster. O(n²) at n ≈ 20–30
 * candidate POIs is effectively instant — no spatial clustering library
 * is needed at this scale.
 *
 * Algorithm:
 *   1. Iterate over unassigned POIs.
 *   2. For each unassigned POI, start a new cluster.
 *   3. Pull in every other unassigned POI within radiusMeters.
 *   4. Compute the cluster anchor as the centroid of its members.
 *
 * This is a pure function — no IO, no side effects.
 */
export function cluster(pois: Poi[], radiusMeters: number): Cluster[] {
  if (pois.length === 0) return [];

  const assigned = new Set<string>();
  const clusters: Cluster[] = [];
  let nextClusterId = 0;

  for (const seed of pois) {
    if (assigned.has(seed.id)) continue;

    const members: Poi[] = [seed];
    assigned.add(seed.id);

    for (const candidate of pois) {
      if (assigned.has(candidate.id)) continue;
      if (haversineMeters(seed.location, candidate.location) <= radiusMeters) {
        members.push(candidate);
        assigned.add(candidate.id);
      }
    }

    clusters.push({
      id: nextClusterId++,
      pois: members,
      anchor: centroid(members),
    });
  }

  return clusters;
}

// ---------------------------------------------------------------------------
// Haversine distance — good enough for the clustering radius check at the
// scale of a single city. No external dependency needed.
// ---------------------------------------------------------------------------

const EARTH_RADIUS_METERS = 6_371_000;

function toRadians(degrees: number): number {
  return (degrees * Math.PI) / 180;
}

export function haversineMeters(a: Coordinate, b: Coordinate): number {
  const dLat = toRadians(b.lat - a.lat);
  const dLng = toRadians(b.lng - a.lng);
  const sinHalfDLat = Math.sin(dLat / 2);
  const sinHalfDLng = Math.sin(dLng / 2);
  const h =
    sinHalfDLat * sinHalfDLat +
    Math.cos(toRadians(a.lat)) * Math.cos(toRadians(b.lat)) * sinHalfDLng * sinHalfDLng;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt(h));
}

function centroid(pois: Poi[]): Coordinate {
  let sumLat = 0;
  let sumLng = 0;
  for (const p of pois) {
    sumLat += p.location.lat;
    sumLng += p.location.lng;
  }
  return { lat: sumLat / pois.length, lng: sumLng / pois.length };
}
