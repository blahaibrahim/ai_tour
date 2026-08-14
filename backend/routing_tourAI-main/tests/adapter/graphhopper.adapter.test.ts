import { describe, expect, it, vi } from 'vitest';
import {
  GraphHopperAdapter,
  type GraphHopperAdapterConfig,
} from '../../src/adapters/routing-provider/graphhopper.adapter.js';
import { RoutingProviderError } from '../../src/adapters/routing-provider/errors.js';

// Pilot city coordinate pairs (Section 1: pilot city is Algiers).
const PLACE_DES_MARTYRS = { lat: 36.7846, lng: 3.0603 };
const NOTRE_DAME_DAFRIQUE = { lat: 36.8072, lng: 3.0472 };
const JARDIN_DESSAI = { lat: 36.7539, lng: 3.0723 };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/** Casts a vi.fn() mock into GraphHopperAdapterConfig's fetchImpl slot. */
function makeAdapter(
  fetchImpl: ReturnType<typeof vi.fn>,
  extra?: Partial<GraphHopperAdapterConfig>,
): GraphHopperAdapter {
  return new GraphHopperAdapter({
    apiKey: 'test-key',
    fetchImpl: fetchImpl as unknown as typeof fetch,
    ...extra,
  });
}

describe('GraphHopperAdapter', () => {
  describe('getRoute', () => {
    it('parses a real-shaped GraphHopper /route response', async () => {
      // Shape captured from GraphHopper's documented Routing API response
      // (paths[0].distance in meters, .time in ms, .points as GeoJSON
      // LineString when points_encoded=false).
      const fetchImpl = vi.fn().mockResolvedValue(
        jsonResponse({
          paths: [
            {
              distance: 1850.4,
              time: 1_332_000,
              points: {
                type: 'LineString',
                coordinates: [
                  [3.0603, 36.7846],
                  [3.055, 36.79],
                  [3.0472, 36.8072],
                ],
              },
            },
          ],
        }),
      );
      const adapter = makeAdapter(fetchImpl);

      const result = await adapter.getRoute([PLACE_DES_MARTYRS, NOTRE_DAME_DAFRIQUE], 'walking');

      expect(result.distanceMeters).toBe(1850.4);
      expect(result.durationMinutes).toBeCloseTo(22.2, 1);
      expect(result.geometry).toHaveLength(3);
      expect(result.geometry[0]).toEqual({ lat: 36.7846, lng: 3.0603 });
    });

    it('builds the request with lat,lng point params and the foot profile for walking', async () => {
      const fetchImpl = vi
        .fn()
        .mockResolvedValue(
          jsonResponse({ paths: [{ distance: 100, time: 60_000, points: { coordinates: [] } }] }),
        );
      const adapter = makeAdapter(fetchImpl);

      await adapter.getRoute([PLACE_DES_MARTYRS, NOTRE_DAME_DAFRIQUE], 'walking');

      const calledUrl = new URL(fetchImpl.mock.calls[0]?.[0] as string);
      expect(calledUrl.searchParams.getAll('point')).toEqual(['36.7846,3.0603', '36.8072,3.0472']);
      expect(calledUrl.searchParams.get('profile')).toBe('foot');
      expect(calledUrl.searchParams.get('key')).toBe('test-key');
    });

    it('throws RoutingProviderError on a malformed response', async () => {
      const fetchImpl = vi.fn().mockResolvedValue(jsonResponse({ paths: [] }));
      const adapter = makeAdapter(fetchImpl);

      await expect(
        adapter.getRoute([PLACE_DES_MARTYRS, NOTRE_DAME_DAFRIQUE], 'walking'),
      ).rejects.toThrow(RoutingProviderError);
    });
  });

  describe('getMatrix', () => {
    it('parses a real-shaped GraphHopper /matrix response and converts seconds to minutes', async () => {
      // Shape captured from GraphHopper's documented Matrix API response
      // (times in seconds, distances in meters, NxN row-major arrays).
      const fetchImpl = vi.fn().mockResolvedValue(
        jsonResponse({
          times: [
            [0, 480, 900],
            [480, 0, 660],
            [900, 660, 0],
          ],
          distances: [
            [0, 1850, 3200],
            [1850, 0, 2600],
            [3200, 2600, 0],
          ],
        }),
      );
      const adapter = makeAdapter(fetchImpl);

      const points = [PLACE_DES_MARTYRS, NOTRE_DAME_DAFRIQUE, JARDIN_DESSAI];
      const matrix = await adapter.getMatrix(points, 'driving');

      expect(matrix.durationsMinutes[0]?.[1]).toBe(8);
      expect(matrix.distancesMeters[0]?.[1]).toBe(1850);
      expect(matrix.points).toBe(points);
    });

    it('sends from_points/to_points as [lng, lat] pairs and the car vehicle for driving', async () => {
      const fetchImpl = vi.fn().mockResolvedValue(jsonResponse({ times: [[0]], distances: [[0]] }));
      const adapter = makeAdapter(fetchImpl);

      await adapter.getMatrix([PLACE_DES_MARTYRS], 'driving');

      const [url, init] = fetchImpl.mock.calls[0] as [string, RequestInit];
      expect(url).toContain('/matrix?key=test-key');
      const body = JSON.parse(init.body as string);
      expect(body.from_points).toEqual([[3.0603, 36.7846]]);
      expect(body.vehicle).toBe('car');
    });
  });

  describe('getIsochrone', () => {
    it('parses a real-shaped GraphHopper /isochrone response', async () => {
      const fetchImpl = vi.fn().mockResolvedValue(
        jsonResponse({
          polygons: [
            {
              type: 'Feature',
              properties: { bucket: 0 },
              geometry: {
                type: 'Polygon',
                coordinates: [
                  [
                    [3.05, 36.78],
                    [3.07, 36.78],
                    [3.07, 36.8],
                    [3.05, 36.8],
                    [3.05, 36.78],
                  ],
                ],
              },
            },
          ],
        }),
      );
      const adapter = makeAdapter(fetchImpl);

      const result = await adapter.getIsochrone(PLACE_DES_MARTYRS, 30, 'walking');

      expect(result.polygon.type).toBe('Polygon');
      expect(result.polygon.coordinates[0]).toHaveLength(5);
      expect(result.timeBudgetMinutes).toBe(30);
    });
  });

  describe('error handling', () => {
    it('throws a "timeout" RoutingProviderError when the request exceeds timeoutMs', async () => {
      const neverResolvingFetch = vi.fn((_url: string, init?: RequestInit) => {
        return new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener('abort', () => {
            const err = new Error('The operation was aborted');
            err.name = 'AbortError';
            reject(err);
          });
        });
      });
      const adapter = makeAdapter(neverResolvingFetch, { timeoutMs: 10 });

      const error: RoutingProviderError = await adapter
        .getRoute([PLACE_DES_MARTYRS, NOTRE_DAME_DAFRIQUE], 'walking')
        .catch((e) => e);

      expect(error).toBeInstanceOf(RoutingProviderError);
      expect(error.code).toBe('timeout');
    });

    it('throws a "request_failed" RoutingProviderError on a non-2xx response', async () => {
      const fetchImpl = vi.fn().mockResolvedValue(new Response('Cannot find point', { status: 400 }));
      const adapter = makeAdapter(fetchImpl);

      const error: RoutingProviderError = await adapter
        .getRoute([PLACE_DES_MARTYRS, NOTRE_DAME_DAFRIQUE], 'walking')
        .catch((e) => e);

      expect(error).toBeInstanceOf(RoutingProviderError);
      expect(error.code).toBe('request_failed');
    });
  });
});
