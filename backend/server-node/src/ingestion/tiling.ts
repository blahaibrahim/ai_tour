/**
 * Deterministic tile covering for the POI cache (docs/backend/12).
 *
 * docs/backend/12 suggests geohash precision 5 or H3 resolution 7 for this.
 * Both need an extra dependency and, for geohash, a non-trivial neighbour
 * algorithm to correctly enumerate a covering set. A plain equirectangular
 * degree grid gives the same operational property that actually matters here
 * — a deterministic, reusable cache key per patch of ground, so repeated
 * queries over the same area hit the cache instead of re-fetching — with about
 * 15 lines of code and zero dependencies. Swapping to geohash/H3 later only
 * touches this file; every caller just consumes `tileId` strings and
 * [latMin, latMax, lngMin, lngMax] bounds.
 */

// ~0.045 degrees of latitude is ~5 km, matching docs/backend/12's target
// cell size. Longitude cells are the same angular size, so they're narrower
// in km than in latitude the further from the equator — irrelevant here
// since tiles are only ever used as opaque cache keys, never for distance
// math (PostGIS geography handles all real distance calculations).
export const TILE_SIZE_DEG = 0.045;

/**
 * Bounds a single ingestion call: a 500 km radius could otherwise expand to
 * thousands of tiles, each a real Overpass + Wikidata round trip. Radius
 * itself is already capped in routes/poi.ts; this is the second, independent
 * cap specifically on *new* fetches per call — a warm cache can still answer
 * a wide query instantly, this only limits how much *uncached* ground one
 * request will pay to fill in. See docs/backend/12's "Pre-warming" note:
 * systematic backfill of a wide area is a job for a scheduled task, not a
 * side effect of one user's request.
 *
 * Started at 9 (a 3x3 grid); cut to 3 after empirically hitting Overpass's
 * rate limit (HTTP 429) partway through manual testing of this pipeline —
 * each tile costs one Overpass call, one Wikidata call, and several
 * Wikipedia/Commons calls, so even a modest tile count adds up fast against
 * free public infrastructure with real fair-use limits.
 */
export const MAX_TILES_PER_INGEST = 3;

function bin(value: number): number {
  return Math.floor(value / TILE_SIZE_DEG);
}

export function tileIdFor(lat: number, lng: number): string {
  return `${bin(lat)}_${bin(lng)}`;
}

/** Returns [latMin, latMax, lngMin, lngMax] for a tile id. */
export function tileBounds(tileId: string): [number, number, number, number] {
  const [latBinStr, lngBinStr] = tileId.split("_");
  const latBin = Number.parseInt(latBinStr, 10);
  const lngBin = Number.parseInt(lngBinStr, 10);
  return [
    latBin * TILE_SIZE_DEG,
    (latBin + 1) * TILE_SIZE_DEG,
    lngBin * TILE_SIZE_DEG,
    (lngBin + 1) * TILE_SIZE_DEG,
  ];
}

/**
 * Tile ids whose bounding boxes intersect the query circle, nearest the
 * center first (so truncation by MAX_TILES_PER_INGEST drops the tiles
 * least likely to matter).
 */
export function coveringTiles(lat: number, lng: number, radiusKm: number): string[] {
  const latPadDeg = radiusKm / 111.0;
  // Longitude degrees shrink towards the poles; guard against cos(lat)==0
  // at the poles even though this app's whole coverage area (Algeria) is
  // nowhere near them — cheap insurance against a future caller passing
  // an unexpected latitude.
  const cosLat = Math.max(Math.cos((lat * Math.PI) / 180), 1e-6);
  const lngPadDeg = radiusKm / (111.0 * cosLat);

  const latMinBin = bin(lat - latPadDeg);
  const latMaxBin = bin(lat + latPadDeg);
  const lngMinBin = bin(lng - lngPadDeg);
  const lngMaxBin = bin(lng + lngPadDeg);

  const candidates: Array<{ distKm: number; tileId: string }> = [];
  for (let latBin = latMinBin; latBin <= latMaxBin; latBin++) {
    for (let lngBin = lngMinBin; lngBin <= lngMaxBin; lngBin++) {
      const tileLat = (latBin + 0.5) * TILE_SIZE_DEG;
      const tileLng = (lngBin + 0.5) * TILE_SIZE_DEG;
      const dLat = (tileLat - lat) * 111.0;
      const dLng = (tileLng - lng) * 111.0 * cosLat;
      candidates.push({ distKm: Math.hypot(dLat, dLng), tileId: `${latBin}_${lngBin}` });
    }
  }

  candidates.sort((a, b) => a.distKm - b.distKm);
  return candidates.slice(0, MAX_TILES_PER_INGEST).map((c) => c.tileId);
}
