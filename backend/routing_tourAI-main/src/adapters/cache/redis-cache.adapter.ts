import { Redis } from 'ioredis';
import type { CacheAdapter } from '../../domain/ports/cache-adapter.port.js';
import type { DurationMatrix, IsochronePolygon } from '../../domain/models/routing.model.js';

export interface RedisCacheAdapterConfig {
  /** An already-connected ioredis client — see redis-client.ts. Connection
   * lifecycle is owned by the composition root, not this adapter, the
   * same dependency-injection pattern GraphHopperAdapter uses for
   * fetchImpl. */
  client: Redis;
  /**
   * Safety-net TTL, not the primary invalidation mechanism — Section 8's
   * nightly warm job is what's meant to keep entries fresh day to day.
   * This just bounds how stale a value can get if that job ever fails to
   * run. Default: 26h, comfortably past a single day's cycle.
   */
  matrixTtlSeconds?: number;
  isochroneTtlSeconds?: number;
}

const DEFAULT_TTL_SECONDS = 26 * 60 * 60;

/**
 * Redis-backed CacheAdapter (Section 3/9) — the swap-in for
 * InMemoryCacheAdapter once Redis is running. Identical interface, so
 * nothing upstream of CacheAdapter (Domain, Orchestration once built)
 * needs to change to use this instead; only the composition root's
 * wiring changes.
 *
 * Keys are prefixed with `route-gen:` since Redis is commonly shared
 * across services/environments — the in-memory implementation doesn't
 * need this since its Map is already scoped to one process.
 */
export class RedisCacheAdapter implements CacheAdapter {
  private readonly client: Redis;
  private readonly matrixTtlSeconds: number;
  private readonly isochroneTtlSeconds: number;

  constructor(config: RedisCacheAdapterConfig) {
    this.client = config.client;
    this.matrixTtlSeconds = config.matrixTtlSeconds ?? DEFAULT_TTL_SECONDS;
    this.isochroneTtlSeconds = config.isochroneTtlSeconds ?? DEFAULT_TTL_SECONDS;
  }

  async getMatrix(cityId: string, mode: string): Promise<DurationMatrix | null> {
    const raw = await this.client.get(matrixKey(cityId, mode));
    return raw ? (JSON.parse(raw) as DurationMatrix) : null;
  }

  async setMatrix(cityId: string, mode: string, matrix: DurationMatrix): Promise<void> {
    await this.client.set(
      matrixKey(cityId, mode),
      JSON.stringify(matrix),
      'EX',
      this.matrixTtlSeconds,
    );
  }

  async getIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
  ): Promise<IsochronePolygon | null> {
    const raw = await this.client.get(isochroneKey(poiId, timeBucket, mode));
    return raw ? (JSON.parse(raw) as IsochronePolygon) : null;
  }

  async setIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
    polygon: IsochronePolygon,
  ): Promise<void> {
    await this.client.set(
      isochroneKey(poiId, timeBucket, mode),
      JSON.stringify(polygon),
      'EX',
      this.isochroneTtlSeconds,
    );
  }
}

function matrixKey(cityId: string, mode: string): string {
  return `route-gen:matrix:${cityId}:${mode}`;
}

function isochroneKey(poiId: string, timeBucket: number, mode: string): string {
  return `route-gen:isochrone:${poiId}:${timeBucket}:${mode}`;
}
