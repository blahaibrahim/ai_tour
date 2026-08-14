import { describe, expect, it } from 'vitest';
import { GraphHopperAdapter } from '../../src/adapters/routing-provider/graphhopper.adapter.js';

// Section 9 Step 2 / Section 11: "validated against the real provider
// using 2–3 fixed coordinate pairs (manual/one-time integration check)."
//
// This test hits the live GraphHopper API and spends real free-tier
// credits, so it's skipped unless ROUTING_PROVIDER_GRAPHHOPPER_API_KEY is
// set — it never runs in CI, and it never ran in the sandbox that built
// this adapter (no network egress to graphhopper.com is available
// there). Run it yourself once you have a key:
//
//   ROUTING_PROVIDER_GRAPHHOPPER_API_KEY=your_key npx vitest run tests/adapter/graphhopper.adapter.integration.test.ts

const apiKey = process.env.ROUTING_PROVIDER_GRAPHHOPPER_API_KEY;

// Pilot city coordinate pairs (Section 1: pilot city is Algiers).
const PLACE_DES_MARTYRS = { lat: 36.7846, lng: 3.0603 };
const NOTRE_DAME_DAFRIQUE = { lat: 36.8072, lng: 3.0472 };
const JARDIN_DESSAI = { lat: 36.7539, lng: 3.0723 };

describe.skipIf(!apiKey)('GraphHopperAdapter — live integration (Algiers)', () => {
  // Free-tier GraphHopper can take 5–8s on cold starts; 3s default is too tight.
  const adapter = new GraphHopperAdapter({ apiKey: apiKey!, timeoutMs: 10_000 });

  it('getRoute returns a plausible walking route between two real Algiers POIs', async () => {
    const result = await adapter.getRoute([PLACE_DES_MARTYRS, NOTRE_DAME_DAFRIQUE], 'walking');
    expect(result.durationMinutes).toBeGreaterThan(0);
    expect(result.distanceMeters).toBeGreaterThan(0);
    expect(result.geometry.length).toBeGreaterThan(0);
  });

  it('getMatrix returns a plausible NxN matrix for 3 real Algiers POIs', async () => {
    const points = [PLACE_DES_MARTYRS, NOTRE_DAME_DAFRIQUE, JARDIN_DESSAI];
    const matrix = await adapter.getMatrix(points, 'driving');
    expect(matrix.durationsMinutes).toHaveLength(3);
    expect(matrix.durationsMinutes[0]).toHaveLength(3);
    expect(matrix.durationsMinutes[0]?.[0]).toBe(0);
    expect(matrix.durationsMinutes[0]?.[1]).toBeGreaterThan(0);
  });
});
