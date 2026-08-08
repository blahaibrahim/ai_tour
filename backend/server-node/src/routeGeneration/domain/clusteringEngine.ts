/**
 * Layer 3 — Clustering Engine. Pure function, no dependencies.
 *
 * Groups POIs into walkable clusters by the city's configured radius. This is
 * the half of the hybrid transport model that decides what "walk this loop"
 * means: everything inside a cluster is walked between, and the drive legs
 * only ever run cluster-anchor to cluster-anchor (spec §5).
 *
 * STATUS: stub. Build this first — it and the Response Assembler are the two
 * components with no dependencies at all (spec §9 step 4).
 *
 * Algorithm, as specified: fixed-radius greedy grouping. POIs within the
 * city's configured radius (default 500 m) of each other join a cluster.
 * O(n²) at n ≈ 20–30 candidate POIs is effectively instant — no spatial
 * clustering library is needed at this scale, and adding one would be a
 * dependency bought for nothing.
 *
 * Two details the implementation has to settle, neither of which the spec
 * fixes, so decide them deliberately rather than by accident:
 *   • Whether the radius test is POI-to-seed or POI-to-any-cluster-member.
 *     The second chains, so a line of POIs 400 m apart becomes one long
 *     cluster that is not actually walkable end to end.
 *   • The anchor. Centroid is the obvious choice, but a centroid can land in
 *     the sea or inside a block with no road access, and it is what the
 *     driving legs route to. The nearest POI to the centroid is safer.
 */
import { NotImplementedError } from "../errors";
import { Cluster, Poi } from "../types";

/** Spec §7, transcribed: `ClusteringEngine.cluster(pois, radiusMeters)`. */
export function cluster(_pois: Poi[], _radiusMeters: number): Cluster[] {
  throw new NotImplementedError("ClusteringEngine.cluster");
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
