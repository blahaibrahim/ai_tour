import type { DurationMatrix, IsochronePolygon } from '../models/routing.model.js';

/**
 * Wraps whatever cache backend sits behind it — an in-memory dictionary
 * during early build (Section 9, Step 2), Redis later (Section 3).
 * Checked before every RoutingProviderAdapter call (Section 2:
 * "Cache-first on every Adapter call").
 *
 * Signatures match Section 7, with Promise<> added so the in-memory
 * implementation honors the same async contract from day one — swapping
 * in the real Redis-backed adapter later must not change any call site.
 */
export interface CacheAdapter {
  getMatrix(cityId: string, mode: string): Promise<DurationMatrix | null>;
  setMatrix(cityId: string, mode: string, matrix: DurationMatrix): Promise<void>;
  getIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
  ): Promise<IsochronePolygon | null>;
  setIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
    polygon: IsochronePolygon,
  ): Promise<void>;
}
