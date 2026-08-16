import fs from "node:fs/promises";
import path from "node:path";

/**
 * Algeria's wilayas, from the same `assets/dz_wilayas.geojson` the Flutter app
 * draws its map from (`lib/utils/geojson_parser.dart`) — 69 features, so the
 * file splits some of the 58 official wilayas; the codes are unique either
 * way, and using the same file is what matters. The copy in
 * `public/` is what the browser fetches to draw the map; this module reads it
 * server-side to answer "which wilaya is this POI in", so the two surfaces
 * always agree about where a boundary is.
 */

export interface Wilaya {
  /** The official two-digit code, e.g. "16" for Algiers. */
  code: string;
  name: string;
  /** Outer rings only — holes and islands don't change which wilaya a POI is in. */
  rings: [number, number][][];
  /** [minLon, minLat, maxLon, maxLat]; the cheap reject before ray casting. */
  bbox: [number, number, number, number];
}

interface Feature {
  properties: { code?: string | number; name?: string };
  geometry: { type: string; coordinates: unknown } | null;
}

let cached: Wilaya[] | null = null;

export async function loadWilayas(): Promise<Wilaya[]> {
  if (cached) return cached;

  const raw = await fs.readFile(
    path.join(process.cwd(), "public", "dz_wilayas.geojson"),
    "utf8",
  );
  const { features } = JSON.parse(raw) as { features: Feature[] };

  cached = features.flatMap((feature) => {
    if (!feature.geometry) return [];

    const rings: [number, number][][] =
      feature.geometry.type === "Polygon"
        ? [(feature.geometry.coordinates as [number, number][][])[0]]
        : feature.geometry.type === "MultiPolygon"
          ? (feature.geometry.coordinates as [number, number][][][]).map(
              (polygon) => polygon[0],
            )
          : [];
    if (rings.length === 0) return [];

    let minLon = Infinity;
    let minLat = Infinity;
    let maxLon = -Infinity;
    let maxLat = -Infinity;
    for (const ring of rings) {
      for (const [lon, lat] of ring) {
        if (lon < minLon) minLon = lon;
        if (lat < minLat) minLat = lat;
        if (lon > maxLon) maxLon = lon;
        if (lat > maxLat) maxLat = lat;
      }
    }

    return [
      {
        code: String(feature.properties.code ?? "").padStart(2, "0"),
        name: feature.properties.name ?? "Unknown",
        rings,
        bbox: [minLon, minLat, maxLon, maxLat] as [number, number, number, number],
      },
    ];
  });

  return cached;
}

/** Crossing-number ray cast, the same test the app uses. */
function inRing(lon: number, lat: number, ring: [number, number][]): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    if (yi > lat !== yj > lat && lon < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

/**
 * Which wilaya a coordinate falls in, or null for a point outside every
 * boundary — which happens for a POI right on the coast, where the simplified
 * outlines in the GeoJSON cut inside the real shoreline.
 */
export function wilayaAt(
  wilayas: Wilaya[],
  lat: number,
  lon: number,
): Wilaya | null {
  for (const wilaya of wilayas) {
    const [minLon, minLat, maxLon, maxLat] = wilaya.bbox;
    if (lon < minLon || lon > maxLon || lat < minLat || lat > maxLat) continue;
    if (wilaya.rings.some((ring) => inRing(lon, lat, ring))) return wilaya;
  }
  return null;
}

/**
 * Nearest wilaya by centre-of-bounding-box, for the coastal misses above.
 * Crude, and only ever asked after [wilayaAt] has already said "nowhere" — a
 * POI 200 m off a simplified coastline lands in the wilaya it is next to.
 */
export function nearestWilaya(
  wilayas: Wilaya[],
  lat: number,
  lon: number,
): Wilaya | null {
  let best: Wilaya | null = null;
  let bestDistance = Infinity;

  for (const wilaya of wilayas) {
    const [minLon, minLat, maxLon, maxLat] = wilaya.bbox;
    // Distance to the box itself, not its centre: a POI just off the coast of
    // a long wilaya is close to its edge and far from its middle.
    const dx = Math.max(minLon - lon, 0, lon - maxLon);
    const dy = Math.max(minLat - lat, 0, lat - maxLat);
    const distance = dx * dx + dy * dy;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = wilaya;
    }
  }
  return best;
}
