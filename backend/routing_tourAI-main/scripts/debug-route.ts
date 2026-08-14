/**
 * Debug script: reproduces the exact flow that `/api/v1/routes/generate`
 * takes, but with verbose logging at each step so we can pinpoint the failure.
 */
import { loadEnv } from '../src/config/env.js';
import { GraphHopperAdapter } from '../src/adapters/routing-provider/graphhopper.adapter.js';
import { InMemoryCacheAdapter } from '../src/adapters/cache/in-memory-cache.adapter.js';
import {
  ALGIERS_CITY_ID,
  ALGIERS_CITY_CONFIG,
  FIXTURE_POIS,
  THEME_CATEGORY_MAP,
} from '../src/data/fixtures/algiers-pois.fixture.js';
import { InMemoryPoiRepository } from '../src/data/repositories/poi.repository.js';
import { InMemoryCityConfigRepository } from '../src/data/repositories/city-config.repository.js';
import { PoiSelector } from '../src/domain/services/poi-selector/index.js';
import { RouteGenerationOrchestrator } from '../src/orchestration/route-generation.orchestrator.js';

const env = loadEnv();

console.log('=== Debug Route Generation ===');
console.log('API Key:', env.ROUTING_PROVIDER_GRAPHHOPPER_API_KEY ? '✅ present' : '❌ missing');
console.log('Timeout:', env.ROUTING_PROVIDER_TIMEOUT_MS, 'ms');

const routingProvider = new GraphHopperAdapter({
  apiKey: env.ROUTING_PROVIDER_GRAPHHOPPER_API_KEY,
  timeoutMs: env.ROUTING_PROVIDER_TIMEOUT_MS,
});

const cache = new InMemoryCacheAdapter();
const poiRepository = new InMemoryPoiRepository(FIXTURE_POIS);
const cityConfigRepository = new InMemoryCityConfigRepository([ALGIERS_CITY_CONFIG]);
const poiSelector = new PoiSelector(poiRepository, THEME_CATEGORY_MAP);

// Step 1: test the POI selector for 'nature'
console.log('\n--- Step 1: POI Selection ---');
const pois = await poiSelector.select(ALGIERS_CITY_ID, 'nature');
console.log(`Selected ${pois.length} nature POIs:`);
for (const p of pois) {
  console.log(`  - ${p.nameEn} (${p.location.lat}, ${p.location.lng})`);
}

// Step 2: test the Matrix API directly
console.log('\n--- Step 2: Matrix API test (driving, 2 points) ---');
try {
  const testPoints = pois.slice(0, 2).map(p => p.location);
  console.log('Points:', testPoints);
  const matrix = await routingProvider.getMatrix(testPoints, 'driving');
  console.log('Matrix result:', JSON.stringify(matrix, null, 2));
} catch (err: any) {
  console.error('Matrix FAILED:', err.message);
  console.error('Code:', err.code);
  console.error('Cause:', err.cause?.message ?? 'none');
}

// Step 3: test the full orchestrator
console.log('\n--- Step 3: Full Orchestrator ---');
const orchestrator = new RouteGenerationOrchestrator({
  routingProvider,
  cache,
  cityConfigRepository,
  poiSelector,
});

try {
  const route = await orchestrator.generate({
    cityId: ALGIERS_CITY_ID,
    theme: 'nature',
    timeBudgetMinutes: 180,
  });
  console.log('✅ Route generated successfully!');
  console.log(`Waypoints: ${route.waypoints.length}`);
  console.log(`Segments: ${route.segments.length}`);
  console.log(`Est. duration: ${route.estimatedTotalDurationMinutes} min`);
} catch (err: any) {
  console.error('❌ Orchestrator FAILED:', err.message);
  console.error('Code:', err.code);
  console.error('Provider:', err.provider);
  if (err.cause) console.error('Cause:', err.cause);
}
