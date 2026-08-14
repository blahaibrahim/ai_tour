/**
 * Layer 3 — Clustering Engine. Pure function, no dependencies.
 *
 * Groups POIs into walkable clusters by the city's configured radius. This is
 * the half of the hybrid transport model that decides what "walk this loop"
 * means: everything inside a cluster is walked between, and the drive legs
 * only ever run cluster-anchor to cluster-anchor (spec §5).
 *
 * Algorithm, as specified: fixed-radius greedy grouping. POIs within the
 * city's configured radius (default 500 m) of each other join a cluster.
 * O(n²) at n ≈ 20–30 candidate POIs is effectively instant — no spatial
 * clustering library is needed at this scale, and adding one would be a
 * dependency bought for nothing.
 *
 * ## The two details the spec leaves open, decided
 *
 * **The radius test is POI-to-seed, not POI-to-any-member.** Testing against
 * any member chains: a line of POIs 400 m apart each join their neighbour's
 * cluster and the whole line becomes one cluster, which is then described to
 * the traveller as walkable when the ends may be kilometres apart. Seed-based
 * grouping bounds every cluster's diameter at 2× the radius by construction,
 * so "walkable" stays true whatever shape the POIs are in.
 *
 * **The anchor is the member nearest the centroid, not the centroid itself.**
 * The anchor is what the driving legs route *to*, and a centroid is a purely
 * geometric point — for a cluster hugging a bay it lands in the water, and for
 * one ringing a block it lands inside the block with no road access. Both make
 * the routing provider snap to whatever road it can find, or fail. A real POI
 * is somewhere a road demonstrably reaches, because someone visits it.
 *
 * Seeds are taken in descending cluster size rather than input order, so a
 * dense group is not broken up by an outlier that happened to be iterated
 * first and claimed two of its members.
 */
import { Cluster, Coordinate, Poi } from "../types";

/** Spec §7, transcribed: `ClusteringEngine.cluster(pois, radiusMeters)`. */
export function cluster(pois: Poi[], radiusMeters: number): Cluster[] {
  if (pois.length === 0) return [];

  // Precompute the full distance matrix once: it is read O(n) times per seed
  // candidate below, and at n ≈ 30 the whole thing is under a thousand
  // haversines.
  const distances = pois.map((a) => pois.map((b) => distanceMeters(a.location, b.location)));

  const assigned = new Set<number>();
  const clusters: Cluster[] = [];

  while (assigned.size < pois.length) {
    // Pick the seed that would gather the most unassigned neighbours. This is
    // what stops an outlier claiming members of a group it is only marginally
    // near, which then leaves that group split across two clusters.
    let bestSeed = -1;
    let bestCount = -1;
    for (let i = 0; i < pois.length; i++) {
      if (assigned.has(i)) continue;
      let count = 0;
      for (let j = 0; j < pois.length; j++) {
        if (!assigned.has(j) && distances[i]![j]! <= radiusMeters) count++;
      }
      if (count > bestCount) {
        bestCount = count;
        bestSeed = i;
      }
    }
    if (bestSeed === -1) break;

    const memberIndices: number[] = [];
    for (let j = 0; j < pois.length; j++) {
      if (!assigned.has(j) && distances[bestSeed]![j]! <= radiusMeters) {
        memberIndices.push(j);
        assigned.add(j);
      }
    }

    const members = memberIndices.map((i) => pois[i]!);
    clusters.push({
      id: clusters.length,
      pois: members,
      anchor: anchorFor(members),
    });
  }

  return clusters;
}

/**
 * The cluster's routing anchor: whichever member sits closest to the
 * geometric centroid. See the module docstring for why not the centroid.
 */
function anchorFor(members: Poi[]): Coordinate {
  if (members.length === 1) return members[0]!.location;

  const centroid: Coordinate = {
    lat: members.reduce((sum, p) => sum + p.location.lat, 0) / members.length,
    lng: members.reduce((sum, p) => sum + p.location.lng, 0) / members.length,
  };

  let best = members[0]!;
  let bestDistance = Infinity;
  for (const p of members) {
    const d = distanceMeters(centroid, p.location);
    if (d < bestDistance) {
      bestDistance = d;
      best = p;
    }
  }
  return best.location;
}

/**
 * Great-circle metres between two points.
 *
 * Provided because clustering, the anchor choice and the day-count check all
 * need it, and it is not worth three copies. Equirectangular would be fine at
 * a 500 m threshold, but this is used for longer spans too.
 */
export function distanceMeters(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const R = 6_371_000;
  const toRad = (deg: number): number => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
