import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { createApp } from '../../src/api/composition-root.js';
import type { FastifyInstance } from 'fastify';
import { ALGIERS_CITY_ID } from '../../src/data/fixtures/algiers-pois.fixture.js';
import { ORAN_CITY_ID } from '../../src/data/fixtures/oran-pois.fixture.js';
import { CONSTANTINE_CITY_ID } from '../../src/data/fixtures/constantine-pois.fixture.js';

let app: FastifyInstance;

beforeAll(async () => {
  const result = await createApp({
    ROUTING_PROVIDER_GRAPHHOPPER_API_KEY: undefined,
  });
  app = result.app;
  await app.ready();
});

afterAll(async () => {
  await app.close();
});

describe('POST /api/v1/routes/generate', () => {
  it('generates a heritage route for Algiers', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/routes/generate',
      payload: {
        cityId: ALGIERS_CITY_ID,
        theme: 'heritage',
        timeBudgetMinutes: 180,
      },
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.cityId).toBe(ALGIERS_CITY_ID);
    expect(body.theme).toBe('heritage');
    expect(body.transportMode).toBeDefined();
    expect(body.segments.length).toBeGreaterThan(0);
    expect(body.waypoints.length).toBeGreaterThan(0);
    expect(body.estimatedTotalDurationMinutes).toBeGreaterThan(0);
    expect(body.dayCountFlag).toBeGreaterThanOrEqual(1);
    expect(body.id).toBeDefined(); // persisted UUID
    expect(body.generatedAt).toBeDefined();
    expect(body.pipelineMs).toBeGreaterThan(0);
  });

  it('generates a nature route for Oran', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/routes/generate',
      payload: {
        cityId: ORAN_CITY_ID,
        theme: 'nature',
        timeBudgetMinutes: 120,
      },
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.cityId).toBe(ORAN_CITY_ID);
    expect(body.theme).toBe('nature');
    expect(body.waypoints.length).toBeGreaterThan(0);
  });

  it('generates a heritage route for Constantine', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/routes/generate',
      payload: {
        cityId: CONSTANTINE_CITY_ID,
        theme: 'heritage',
        timeBudgetMinutes: 240,
      },
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.cityId).toBe(CONSTANTINE_CITY_ID);
    expect(body.waypoints.length).toBeGreaterThan(0);
  });

  it('returns 404 for an unknown city', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/routes/generate',
      payload: {
        cityId: '00000000-0000-0000-0000-000000000000',
        theme: 'heritage',
        timeBudgetMinutes: 60,
      },
    });

    expect(response.statusCode).toBe(404);
    expect(response.json().error).toBe('city_not_found');
  });

  it('returns 404 for a theme with no matching POIs', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/routes/generate',
      payload: {
        cityId: ALGIERS_CITY_ID,
        theme: 'underwater_ruins',
        timeBudgetMinutes: 60,
      },
    });

    expect(response.statusCode).toBe(404);
    expect(response.json().error).toBe('no_pois_found');
  });

  it('returns 400 for an invalid body (missing fields)', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/routes/generate',
      payload: { cityId: ALGIERS_CITY_ID },
    });

    expect(response.statusCode).toBe(400);
  });

  it('returns 400 for timeBudgetMinutes below minimum', async () => {
    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/routes/generate',
      payload: {
        cityId: ALGIERS_CITY_ID,
        theme: 'heritage',
        timeBudgetMinutes: 5,
      },
    });

    expect(response.statusCode).toBe(400);
  });
});

describe('GET /health', () => {
  it('returns ok status', async () => {
    const response = await app.inject({ method: 'GET', url: '/health' });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.status).toBe('ok');
    expect(body.uptime).toBeGreaterThan(0);
    expect(body.cities).toBe(3);
  });
});
