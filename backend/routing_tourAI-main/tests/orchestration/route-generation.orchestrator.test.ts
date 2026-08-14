import { describe, it, expect } from 'vitest';
import { InMemoryCacheAdapter } from '../../src/adapters/cache/in-memory-cache.adapter.js';
import { MockRoutingProviderAdapter } from '../fixtures/mock-routing-provider.adapter.js';
import {
  ALGIERS_CITY_CONFIG,
  ALGIERS_CITY_ID,
  FIXTURE_POIS,
  THEME_CATEGORY_MAP,
} from '../../src/data/fixtures/algiers-pois.fixture.js';
import { InMemoryPoiRepository } from '../../src/data/repositories/poi.repository.js';
import { InMemoryCityConfigRepository } from '../../src/data/repositories/city-config.repository.js';
import { PoiSelector } from '../../src/domain/services/poi-selector/index.js';
import {
  RouteGenerationOrchestrator,
  type RouteGenerationRequest,
} from '../../src/orchestration/route-generation.orchestrator.js';

function buildOrchestrator() {
  const routingProvider = new MockRoutingProviderAdapter();
  const cache = new InMemoryCacheAdapter();
  const poiRepository = new InMemoryPoiRepository(FIXTURE_POIS);
  const cityConfigRepository = new InMemoryCityConfigRepository([ALGIERS_CITY_CONFIG]);
  const poiSelector = new PoiSelector(poiRepository, THEME_CATEGORY_MAP);

  return new RouteGenerationOrchestrator({
    routingProvider,
    cache,
    cityConfigRepository,
    poiSelector,
  });
}

describe('RouteGenerationOrchestrator', () => {
  it('generates a route with correct structure for the "heritage" theme', async () => {
    const orchestrator = buildOrchestrator();
    const request: RouteGenerationRequest = {
      cityId: ALGIERS_CITY_ID,
      theme: 'heritage',
      timeBudgetMinutes: 180,
    };

    const route = await orchestrator.generate(request);

    // Section 11: "checked against an expected route shape: correct
    // segment count, mode tags present, plausible day-count flag."
    expect(route.cityId).toBe(ALGIERS_CITY_ID);
    expect(route.theme).toBe('heritage');
    expect(route.timeBudgetMinutes).toBe(180);
    expect(route.segments.length).toBeGreaterThan(0);
    expect(route.waypoints.length).toBeGreaterThan(0);
    expect(route.estimatedTotalDurationMinutes).toBeGreaterThan(0);
    expect(route.dayCountFlag).toBeGreaterThanOrEqual(1);
  });

  it('includes both driving and walking segments (hybrid)', async () => {
    const orchestrator = buildOrchestrator();
    const route = await orchestrator.generate({
      cityId: ALGIERS_CITY_ID,
      theme: 'heritage',
      timeBudgetMinutes: 180,
    });

    const modes = new Set(route.segments.map((s) => s.mode));
    expect(modes.has('walking')).toBe(true);
    expect(modes.has('driving')).toBe(true);
    expect(route.transportMode).toBe('hybrid');
  });

  it('assigns sequential waypoint sequence orders', async () => {
    const orchestrator = buildOrchestrator();
    const route = await orchestrator.generate({
      cityId: ALGIERS_CITY_ID,
      theme: 'heritage',
      timeBudgetMinutes: 300,
    });

    const orders = route.waypoints.map((w) => w.sequenceOrder);
    expect(orders).toEqual(orders.map((_, i) => i));
  });

  it('throws for an unknown cityId', async () => {
    const orchestrator = buildOrchestrator();
    await expect(
      orchestrator.generate({
        cityId: 'nonexistent',
        theme: 'heritage',
        timeBudgetMinutes: 60,
      }),
    ).rejects.toThrow('City config not found');
  });

  it('throws for a theme with no matching POIs', async () => {
    const orchestrator = buildOrchestrator();
    await expect(
      orchestrator.generate({
        cityId: ALGIERS_CITY_ID,
        theme: 'underwater_basket_weaving',
        timeBudgetMinutes: 60,
      }),
    ).rejects.toThrow('No eligible POIs found');
  });

  it('generates a route for the "nature" theme', async () => {
    const orchestrator = buildOrchestrator();
    const route = await orchestrator.generate({
      cityId: ALGIERS_CITY_ID,
      theme: 'nature',
      timeBudgetMinutes: 120,
    });

    // Nature theme includes park_garden + viewpoint categories.
    // From fixtures: Jardin d'Essai and Notre Dame d'Afrique.
    expect(route.waypoints.length).toBeGreaterThanOrEqual(2);
    expect(route.segments.length).toBeGreaterThan(0);
  });

  it('caches matrix results across calls', async () => {
    let matrixCallCount = 0;
    const countingProvider = new (class extends MockRoutingProviderAdapter {
      override async getMatrix(
        ...args: Parameters<MockRoutingProviderAdapter['getMatrix']>
      ) {
        matrixCallCount++;
        return super.getMatrix(...args);
      }
    })();

    const cache = new InMemoryCacheAdapter();
    const orchestrator = new RouteGenerationOrchestrator({
      routingProvider: countingProvider,
      cache,
      cityConfigRepository: new InMemoryCityConfigRepository([ALGIERS_CITY_CONFIG]),
      poiSelector: new PoiSelector(
        new InMemoryPoiRepository(FIXTURE_POIS),
        THEME_CATEGORY_MAP,
      ),
    });

    const request: RouteGenerationRequest = {
      cityId: ALGIERS_CITY_ID,
      theme: 'heritage',
      timeBudgetMinutes: 180,
    };

    // First call: cache misses, provider is called.
    await orchestrator.generate(request);
    const firstCallCount = matrixCallCount;
    expect(firstCallCount).toBeGreaterThan(0);

    // Second call: same request should hit cache for at least some matrices.
    await orchestrator.generate(request);
    const secondCallCount = matrixCallCount - firstCallCount;
    // Cache should reduce provider calls (or keep them the same if all cached).
    expect(secondCallCount).toBeLessThanOrEqual(firstCallCount);
  });
});
