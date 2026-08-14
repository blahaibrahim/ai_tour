import type { CacheAdapter } from '../../domain/ports/cache-adapter.port.js';
import type { DurationMatrix, IsochronePolygon } from '../../domain/models/routing.model.js';

/**
 * In-memory CacheAdapter implementation (Section 9, Step 2). A plain Map
 * standing in for Redis during early build — same interface, so swapping
 * in RedisCacheAdapter later touches no call sites. Not persistent across
 * process restarts or shared across instances — expected at this stage,
 * and fine for local development against a single process.
 */
export class InMemoryCacheAdapter implements CacheAdapter {
  private readonly matrixStore = new Map<string, DurationMatrix>();
  private readonly isochroneStore = new Map<string, IsochronePolygon>();

  async getMatrix(cityId: string, mode: string): Promise<DurationMatrix | null> {
    return this.matrixStore.get(matrixKey(cityId, mode)) ?? null;
  }

  async setMatrix(cityId: string, mode: string, matrix: DurationMatrix): Promise<void> {
    this.matrixStore.set(matrixKey(cityId, mode), matrix);
  }

  async getIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
  ): Promise<IsochronePolygon | null> {
    return this.isochroneStore.get(isochroneKey(poiId, timeBucket, mode)) ?? null;
  }

  async setIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
    polygon: IsochronePolygon,
  ): Promise<void> {
    this.isochroneStore.set(isochroneKey(poiId, timeBucket, mode), polygon);
  }

  /** Test/debug helper only — not part of the CacheAdapter contract. */
  clear(): void {
    this.matrixStore.clear();
    this.isochroneStore.clear();
  }
}

function matrixKey(cityId: string, mode: string): string {
  return `${cityId}:${mode}`;
}

function isochroneKey(poiId: string, timeBucket: number, mode: string): string {
  return `${poiId}:${timeBucket}:${mode}`;
}
