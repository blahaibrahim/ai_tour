import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Redis } from 'ioredis';
import { RedisCacheAdapter } from '../../src/adapters/cache/redis-cache.adapter.js';
import type { DurationMatrix, IsochronePolygon } from '../../src/domain/models/routing.model.js';

const REDIS_URL = process.env.REDIS_URL ?? 'redis://localhost:6379';

async function isRedisReachable(url: string): Promise<boolean> {
  const probe = new Redis(url, { lazyConnect: true, connectTimeout: 500, maxRetriesPerRequest: 0 });
  try {
    await probe.connect();
    await probe.ping();
    return true;
  } catch {
    return false;
  } finally {
    probe.disconnect();
  }
}

// Runs against a real Redis, not a mock — Redis is local infra (unlike
// GraphHopper, no API key or paid quota involved), so a genuine
// connectivity check here is worth more than mocking ioredis. Skips
// cleanly if Redis isn't running (e.g. `docker compose up -d redis`
// hasn't been run yet) instead of hanging or failing the whole suite.
const redisAvailable = await isRedisReachable(REDIS_URL);

describe.skipIf(!redisAvailable)(
  'RedisCacheAdapter (requires local Redis — docker compose up -d redis)',
  () => {
    let client: Redis;
    let cache: RedisCacheAdapter;

    beforeAll(() => {
      client = new Redis(REDIS_URL);
      cache = new RedisCacheAdapter({ client, matrixTtlSeconds: 2, isochroneTtlSeconds: 2 });
    });

    afterAll(async () => {
      await client.flushdb();
      client.disconnect();
    });

    const matrix = (mode: 'driving' | 'walking'): DurationMatrix => ({
      points: [],
      mode,
      durationsMinutes: [[0]],
      distancesMeters: [[0]],
    });

    it('returns null on a miss and the stored value on a hit', async () => {
      expect(await cache.getMatrix('city-1', 'driving')).toBeNull();

      await cache.setMatrix('city-1', 'driving', matrix('driving'));
      expect(await cache.getMatrix('city-1', 'driving')).toEqual(matrix('driving'));
    });

    it('keys matrix cache by city AND mode independently', async () => {
      await cache.setMatrix('city-2', 'driving', matrix('driving'));
      expect(await cache.getMatrix('city-2', 'walking')).toBeNull();
    });

    it('stores and retrieves isochrones independently by poiId/timeBucket/mode', async () => {
      const polygon: IsochronePolygon = {
        center: { lat: 36.78, lng: 3.06 },
        timeBudgetMinutes: 30,
        mode: 'walking',
        polygon: {
          type: 'Polygon',
          coordinates: [
            [
              [3.06, 36.78],
              [3.07, 36.78],
              [3.07, 36.79],
              [3.06, 36.78],
            ],
          ],
        },
      };
      await cache.setIsochrone('poi-1', 30, 'walking', polygon);
      expect(await cache.getIsochrone('poi-1', 30, 'walking')).toEqual(polygon);
      expect(await cache.getIsochrone('poi-1', 45, 'walking')).toBeNull();
    });

    it('expires entries after the configured TTL (safety net beyond the nightly warm job)', async () => {
      await cache.setMatrix('city-ttl', 'driving', matrix('driving'));
      expect(await cache.getMatrix('city-ttl', 'driving')).toEqual(matrix('driving'));

      await new Promise((resolve) => setTimeout(resolve, 2100)); // TTL configured to 2s above
      expect(await cache.getMatrix('city-ttl', 'driving')).toBeNull();
    });
  },
);
