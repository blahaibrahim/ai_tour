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

describe('GET /api/v1/cities', () => {
  it('returns all 3 cities', async () => {
    const response = await app.inject({ method: 'GET', url: '/api/v1/cities' });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.cities).toHaveLength(3);

    const names = body.cities.map((c: { name: string }) => c.name);
    expect(names).toContain('Algiers');
    expect(names).toContain('Oran');
    expect(names).toContain('Constantine');
  });

  it('returns city details including rollout status', async () => {
    const response = await app.inject({ method: 'GET', url: '/api/v1/cities' });
    const body = response.json();

    for (const city of body.cities) {
      expect(city.rolloutStatus).toBe('pilot');
      expect(city.clusterRadiusMeters).toBeGreaterThan(0);
    }
  });
});

describe('GET /api/v1/cities/:id', () => {
  it('returns Algiers city config', async () => {
    const response = await app.inject({
      method: 'GET',
      url: `/api/v1/cities/${ALGIERS_CITY_ID}`,
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.name).toBe('Algiers');
    expect(body.clusterRadiusMeters).toBe(500);
  });

  it('returns 404 for unknown city id', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/api/v1/cities/nonexistent-id',
    });

    expect(response.statusCode).toBe(404);
    expect(response.json().error).toBe('city_not_found');
  });
});

describe('GET /api/v1/cities/:cityId/pois', () => {
  it('returns all POIs for Algiers', async () => {
    const response = await app.inject({
      method: 'GET',
      url: `/api/v1/cities/${ALGIERS_CITY_ID}/pois`,
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.city.name).toBe('Algiers');
    expect(body.count).toBe(15); // expanded to 15 POIs
    expect(body.pois).toHaveLength(15);
  });

  it('returns only heritage POIs for Oran when theme filter is applied', async () => {
    const response = await app.inject({
      method: 'GET',
      url: `/api/v1/cities/${ORAN_CITY_ID}/pois?theme=heritage`,
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.theme).toBe('heritage');
    expect(body.count).toBeGreaterThan(0);
    expect(body.count).toBeLessThan(10); // Not all 10 Oran POIs are heritage
  });

  it('returns 10 POIs for Constantine (all themes)', async () => {
    const response = await app.inject({
      method: 'GET',
      url: `/api/v1/cities/${CONSTANTINE_CITY_ID}/pois`,
    });

    expect(response.statusCode).toBe(200);
    const body = response.json();
    expect(body.count).toBe(10);
  });

  it('returns 400 for an unknown theme', async () => {
    const response = await app.inject({
      method: 'GET',
      url: `/api/v1/cities/${ALGIERS_CITY_ID}/pois?theme=invalid_theme`,
    });

    expect(response.statusCode).toBe(400);
    expect(response.json().error).toBe('invalid_theme');
  });
});
