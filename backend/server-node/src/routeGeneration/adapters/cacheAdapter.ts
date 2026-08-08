/**
 * Layer 4 — Cache Adapter.
 *
 * Checked before *every* Routing Provider Adapter call, without exception. It
 * is the primary lever on both the latency budget (under 800 ms on a cache
 * hit) and the provider quota (per-minute credits, or 2,500 requests/day) —
 * spec §2 and §10 both call the cache-first rule mandatory rather than an
 * optimization.
 *
 * STATUS: interface plus the in-memory implementation the spec's build order
 * asks for ("Cache Adapter can start as an in-memory dictionary; Redis is a
 * later swap behind the same interface" — §9 step 2). The Redis implementation
 * and the nightly warm job are stubs.
 */
import { getLogger } from "../../logger";
import { NotImplementedError } from "../errors";
import { DurationMatrix, IsochronePolygon } from "../types";

const logger = getLogger("routeGeneration.cache");

/** Spec §7, transcribed. */
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

/**
 * Isochrone budgets are rounded to a bucket before being used as a key.
 *
 * Without this every distinct remaining-budget value in minutes is its own
 * key, so the isochrone cache would never hit — the budget is a running
 * subtraction and effectively continuous.
 */
export const ISOCHRONE_BUCKET_MINUTES = 15;

export function isochroneBucket(minutes: number): number {
  return Math.max(
    ISOCHRONE_BUCKET_MINUTES,
    Math.round(minutes / ISOCHRONE_BUCKET_MINUTES) * ISOCHRONE_BUCKET_MINUTES,
  );
}

/** How long a cached entry is served. POI positions do not move and the road
 * network changes slowly; the nightly warm job refreshes ahead of demand. */
export const MATRIX_TTL_MS = 24 * 60 * 60 * 1000;
export const ISOCHRONE_TTL_MS = 24 * 60 * 60 * 1000;

interface Entry<T> {
  value: T;
  storedAt: number;
}

/**
 * The starting implementation. Process-local, so it is per-instance rather
 * than shared — which is correct for a single deployable service and is
 * exactly what the Redis swap later fixes.
 */
export class InMemoryCacheAdapter implements CacheAdapter {
  private readonly matrices = new Map<string, Entry<DurationMatrix>>();
  private readonly isochrones = new Map<string, Entry<IsochronePolygon>>();

  private static fresh<T>(entry: Entry<T> | undefined, ttlMs: number): T | null {
    if (!entry) return null;
    if (Date.now() - entry.storedAt > ttlMs) return null;
    return entry.value;
  }

  async getMatrix(cityId: string, mode: string): Promise<DurationMatrix | null> {
    return InMemoryCacheAdapter.fresh(this.matrices.get(`${cityId}:${mode}`), MATRIX_TTL_MS);
  }

  async setMatrix(cityId: string, mode: string, matrix: DurationMatrix): Promise<void> {
    this.matrices.set(`${cityId}:${mode}`, { value: matrix, storedAt: Date.now() });
  }

  async getIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
  ): Promise<IsochronePolygon | null> {
    return InMemoryCacheAdapter.fresh(
      this.isochrones.get(`${poiId}:${timeBucket}:${mode}`),
      ISOCHRONE_TTL_MS,
    );
  }

  async setIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
    polygon: IsochronePolygon,
  ): Promise<void> {
    this.isochrones.set(`${poiId}:${timeBucket}:${mode}`, {
      value: polygon,
      storedAt: Date.now(),
    });
  }

  /** Test hook — asserting a cache hit skips the Adapter call entirely is one
   * of the spec's named test cases (§11). */
  clear(): void {
    this.matrices.clear();
    this.isochrones.clear();
  }
}

/** The later swap. Same interface, so nothing above Layer 4 changes. */
export class RedisCacheAdapter implements CacheAdapter {
  getMatrix(_cityId: string, _mode: string): Promise<DurationMatrix | null> {
    throw new NotImplementedError("RedisCacheAdapter.getMatrix");
  }
  setMatrix(_cityId: string, _mode: string, _matrix: DurationMatrix): Promise<void> {
    throw new NotImplementedError("RedisCacheAdapter.setMatrix");
  }
  getIsochrone(
    _poiId: string,
    _timeBucket: number,
    _mode: string,
  ): Promise<IsochronePolygon | null> {
    throw new NotImplementedError("RedisCacheAdapter.getIsochrone");
  }
  setIsochrone(
    _poiId: string,
    _timeBucket: number,
    _mode: string,
    _polygon: IsochronePolygon,
  ): Promise<void> {
    throw new NotImplementedError("RedisCacheAdapter.setIsochrone");
  }
}

let shared: CacheAdapter | null = null;

export function getCacheAdapter(): CacheAdapter {
  if (shared === null) {
    shared = new InMemoryCacheAdapter();
    logger.info("Cache adapter: in-memory (Redis is the later swap, same interface)");
  }
  return shared;
}

/**
 * Nightly scheduled job: refreshes each *active* city's full POI matrix ahead
 * of demand, so the first user request of the day is a cache hit rather than
 * the one that pays for the cold matrix (spec §8).
 *
 * STATUS: stub. Needs the POI repository and the routing adapter first.
 */
export async function warmActiveCityMatrices(): Promise<void> {
  throw new NotImplementedError("warmActiveCityMatrices (nightly matrix warm job)");
}
