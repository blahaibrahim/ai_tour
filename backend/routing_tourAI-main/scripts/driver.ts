/**
 * Minimal driver script (Section 9, Step 6): calls the Orchestrator
 * with multiple sample requests and prints the results — validates the
 * full pipeline end-to-end with different themes and time budgets.
 *
 * Usage: npm run driver
 */

import { createApp } from '../src/api/composition-root.js';
import type { RouteGenerationRequest } from '../src/orchestration/route-generation.orchestrator.js';
import type { RouteResponse } from '../src/domain/models/route.model.js';
import { ALGIERS_CITY_ID, FIXTURE_POIS } from '../src/data/fixtures/algiers-pois.fixture.js';

// ── Scenarios to run ───────────────────────────────────────────────
const SCENARIOS: { label: string; request: RouteGenerationRequest }[] = [
  {
    label: '🏛️  Heritage tour — 3 hours',
    request: { cityId: ALGIERS_CITY_ID, theme: 'heritage', timeBudgetMinutes: 180 },
  },
  {
    label: '🌿  Nature tour — 2 hours',
    request: { cityId: ALGIERS_CITY_ID, theme: 'nature', timeBudgetMinutes: 120 },
  },
  {
    label: '🗺️  All POIs — tight 1 hour budget',
    request: { cityId: ALGIERS_CITY_ID, theme: 'all', timeBudgetMinutes: 60 },
  },
  {
    label: '🗺️  All POIs — generous full-day 8 hours',
    request: { cityId: ALGIERS_CITY_ID, theme: 'all', timeBudgetMinutes: 480 },
  },
];

async function main() {
  console.log('╔═══════════════════════════════════════════════════════╗');
  console.log('║       Route Generation Driver — Multi-Scenario       ║');
  console.log('║              Pilot City: Algiers 🇩🇿                  ║');
  console.log('╚═══════════════════════════════════════════════════════╝\n');

  // Boot the full application context (Postgres, Redis, GraphHopper if available)
  const { deps, app } = await createApp();
  const orchestrator = deps.orchestrator;

  for (let i = 0; i < SCENARIOS.length; i++) {
    const scenario = SCENARIOS[i]!;
    const { label, request } = scenario;

    console.log(`┌─── Scenario ${i + 1}/${SCENARIOS.length}: ${label} ───`);
    console.log(`│  Theme: ${request.theme}  |  Budget: ${request.timeBudgetMinutes} min`);
    console.log('│');

    const startTime = performance.now();
    const route = await orchestrator.generate(request);
    const elapsed = (performance.now() - startTime).toFixed(1);

    printRoute(route, elapsed);

    if (i < SCENARIOS.length - 1) {
      console.log('');
    }
  }

  console.log('\n══════════════════════════════════════════════════════════');
  console.log('All scenarios completed successfully.');
}

function printRoute(route: RouteResponse, elapsed: string) {
  const clusterCount = new Set(route.waypoints.map((w) => w.clusterId)).size;

  console.log(`│  Transport:  ${route.transportMode}`);
  console.log(`│  Clusters:   ${clusterCount}`);
  console.log(`│  Waypoints:  ${route.waypoints.length}`);
  console.log(`│  Segments:   ${route.segments.length}`);
  console.log(`│  Est. time:  ${route.estimatedTotalDurationMinutes} min  (budget: ${route.timeBudgetMinutes} min)`);

  const fits = route.estimatedTotalDurationMinutes <= route.timeBudgetMinutes;
  console.log(
    `│  Day-count:  ${route.dayCountFlag}  ${fits ? '✅ fits in 1 day' : '⚠️  needs ' + route.dayCountFlag + ' day(s)'}`,
  );

  console.log('│');
  console.log('│  Waypoint order:');
  for (const wp of route.waypoints) {
    const poi = FIXTURE_POIS.find((p) => p.id === wp.poiId);
    const name = (poi?.nameEn ?? wp.poiId).padEnd(30);
    console.log(
      `│    #${wp.sequenceOrder} [C${wp.clusterId}] ${name} (${wp.checkpointRadiusMeters}m radius)`,
    );
  }

  console.log('│');
  console.log('│  Segments:');
  const walkSegs = route.segments.filter((s) => s.mode === 'walking');
  const driveSegs = route.segments.filter((s) => s.mode === 'driving');
  console.log(`│    🚶 Walking: ${walkSegs.length} leg(s)`);
  console.log(`│    🚗 Driving: ${driveSegs.length} leg(s)`);

  console.log(`│`);
  console.log(`│  ⏱️  Pipeline: ${elapsed}ms`);
  console.log('└──────────────────────────────────────────────────────');
}

main().catch((err) => {
  console.error('Driver script failed:', err);
  process.exitCode = 1;
});
