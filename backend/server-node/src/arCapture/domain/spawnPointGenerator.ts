/**
 * Layer 3 — Spawn Point Generator. Pure function, no dependencies.
 *
 * Produces a deterministic, seeded, walkable spawn coordinate inside a POI's
 * spawn zone (plan §5.1). "Walkable" is enforced upstream, by the admin
 * spawn-zone editor curating `spawn_zone` from an isochrone minus roads and
 * water before a POI is ever published — this function only has to stay
 * inside whatever polygon it is handed.
 *
 * STATUS: implemented for real — see `proximityBandCalculator.ts`'s status
 * note for why the plan's pure Layer 3 pieces are built rather than stubbed
 * even while the Data layer around them is not.
 */
import * as crypto from "crypto";

import { xoshiro128ss } from "./deterministicRandom";
import type { Coordinate } from "../../routeGeneration/types";

/** A single polygon ring, GeoJSON-style: `[lng, lat]` pairs, first == last. */
export type Ring = Array<[number, number]>;

/** Outer ring plus optional holes — only the outer ring is used here, since
 * plan §5.1's curated spawn zones have no holes in practice. */
export type Polygon = Ring[];

interface BoundingBox {
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
}

function boundingBox(zone: Polygon): BoundingBox {
  const ring = zone[0];
  let minLat = Infinity;
  let maxLat = -Infinity;
  let minLng = Infinity;
  let maxLng = -Infinity;
  for (const [lng, lat] of ring) {
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
  }
  return { minLat, maxLat, minLng, maxLng };
}

function lerp(min: number, max: number, t: number): number {
  return min + (max - min) * t;
}

/** Ray-casting point-in-polygon — the pure-JS stand-in for PostGIS's
 * `ST_Contains` used at runtime once the zone lives in the database (§5.1's
 * pseudocode names `stContains` directly; this is that function without a
 * live database to call it against). */
export function pointInPolygon(point: Coordinate, zone: Polygon): boolean {
  const ring = zone[0];
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    const intersects =
      yi > point.lat !== yj > point.lat &&
      point.lng < ((xj - xi) * (point.lat - yi)) / (yj - yi) + xi;
    if (intersects) inside = !inside;
  }
  return inside;
}

function centroid(zone: Polygon): Coordinate {
  const ring = zone[0];
  let lat = 0;
  let lng = 0;
  // Ring closes on itself (first point repeated last) — drop the repeat so
  // it isn't double-weighted.
  const points = ring.slice(0, -1);
  for (const [pLng, pLat] of points) {
    lat += pLat;
    lng += pLng;
  }
  return { lat: lat / points.length, lng: lng / points.length };
}

const EARTH_RADIUS_M = 6_371_000;

/** Offsets `origin` by `metres` at a `rng()`-drawn bearing — used only by the
 * near-centroid fallback below. */
function jitter(origin: Coordinate, metres: number, rng: () => number): Coordinate {
  const bearing = rng() * 2 * Math.PI;
  const dLat = ((metres * Math.cos(bearing)) / EARTH_RADIUS_M) * (180 / Math.PI);
  const dLng =
    ((metres * Math.sin(bearing)) / (EARTH_RADIUS_M * Math.cos((origin.lat * Math.PI) / 180))) *
    (180 / Math.PI);
  return { lat: origin.lat + dLat, lng: origin.lng + dLng };
}

const MAX_REJECTION_ATTEMPTS = 30;
const FALLBACK_OFFSET_METERS = 10;

/**
 * Rejection-samples a point inside `zone`, per plan §5.1's transcribed
 * pseudocode. Falls back to a small jitter around the polygon's centroid if
 * 30 uniform-in-bounding-box attempts all miss (a plausible outcome for a
 * zone that is a thin sliver of its own bounding box).
 */
export function generateSpawnPoint(zone: Polygon, seed: Buffer): Coordinate {
  const rng = xoshiro128ss(seed);
  const bbox = boundingBox(zone);

  for (let i = 0; i < MAX_REJECTION_ATTEMPTS; i++) {
    const point: Coordinate = {
      lat: lerp(bbox.minLat, bbox.maxLat, rng()),
      lng: lerp(bbox.minLng, bbox.maxLng, rng()),
    };
    if (pointInPolygon(point, zone)) return point;
  }
  return jitter(centroid(zone), FALLBACK_OFFSET_METERS, rng);
}

/**
 * `seed = HMAC-SHA256(serverSecret, routeId ‖ poiId ‖ spawnEpoch)` (plan
 * §5.1). Determinism is the whole point (see the module docstring), and this
 * is what makes the seed unguessable by a client despite being reproducible
 * server-side: nobody without `serverSecret` can predict a spawn point ahead
 * of the manifest that reveals it.
 */
export function deriveSpawnSeed(
  serverSecret: string,
  routeId: string,
  poiId: string,
  spawnEpoch: string,
): Buffer {
  return crypto
    .createHmac("sha256", serverSecret)
    .update(`${routeId}‖${poiId}‖${spawnEpoch}`)
    .digest();
}
