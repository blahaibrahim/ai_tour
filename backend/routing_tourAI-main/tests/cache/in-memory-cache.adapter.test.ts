import { describe, expect, it, vi } from 'vitest';
import { InMemoryCacheAdapter } from '../../src/adapters/cache/in-memory-cache.adapter.js';
import { MockRoutingProviderAdapter } from '../fixtures/mock-routing-provider.adapter.js';
import type { DurationMatrix } from '../../src/domain/models/routing.model.js';

const emptyMatrix = (mode: 'driving' | 'walking'): DurationMatrix => ({
  points: [],
  mode,
  durationsMinutes: [[0]],
  distancesMeters: [[0]],
});

describe('InMemoryCacheAdapter', () => {
  it('returns null on a miss and the stored value on a hit', async () => {
    const cache = new InMemoryCacheAdapter();
    expect(await cache.getMatrix('city-1', 'driving')).toBeNull();

    const matrix = emptyMatrix('driving');
    await cache.setMatrix('city-1', 'driving', matrix);
    expect(await cache.getMatrix('city-1', 'driving')).toEqual(matrix);
  });

  it('keys matrix cache by city AND mode independently', async () => {
    const cache = new InMemoryCacheAdapter();
    await cache.setMatrix('city-1', 'driving', emptyMatrix('driving'));
    expect(await cache.getMatrix('city-1', 'walking')).toBeNull();
    expect(await cache.getMatrix('city-2', 'driving')).toBeNull();
  });

  it('a cache hit means the underlying RoutingProviderAdapter is never called (Section 11)', async () => {
    const cache = new InMemoryCacheAdapter();
    const provider = new MockRoutingProviderAdapter();
    const getMatrixSpy = vi.spyOn(provider, 'getMatrix');

    const points = [
      { lat: 36.78, lng: 3.06 },
      { lat: 36.75, lng: 3.07 },
    ];

    // Simulates the cache-first pattern Orchestration will use in Step 5
    // (Section 2: "Cache-first on every Adapter call").
    async function getMatrixCacheFirst(cityId: string, mode: 'driving' | 'walking') {
      const cached = await cache.getMatrix(cityId, mode);
      if (cached) return cached;
      const fresh = await provider.getMatrix(points, mode);
      await cache.setMatrix(cityId, mode, fresh);
      return fresh;
    }

    const first = await getMatrixCacheFirst('city-1', 'driving');
    const second = await getMatrixCacheFirst('city-1', 'driving');

    expect(getMatrixSpy).toHaveBeenCalledTimes(1);
    expect(second).toEqual(first);
  });
});
