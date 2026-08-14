import { describe, it, expect } from 'vitest';
import {
  estimate,
  pointInPolygon,
} from '../../src/domain/services/time-reachability-estimator/time-reachability-estimator.js';
import type { Poi } from '../../src/domain/models/poi.model.js';
import type { DurationMatrix } from '../../src/domain/models/routing.model.js';
import type { GeoJsonPolygon } from '../../src/domain/models/coordinate.model.js';

function makePoi(id: string, lat: number, lng: number, dwell: number): Poi {
  return {
    id,
    cityId: 'city-1',
    categoryId: 'cat-1',
    nameFr: null,
    nameAr: null,
    nameEn: null,
    location: { lat, lng },
    openingHoursRaw: null,
    avgVisitDurationMinutes: dwell,
    checkpointRadiusMeters: 30,
  };
}

describe('TimeReachabilityEstimator', () => {
  describe('estimate', () => {
    it('returns zero for an empty stop list', () => {
      const matrix: DurationMatrix = {
        points: [],
        mode: 'walking',
        durationsMinutes: [],
        distancesMeters: [],
      };
      const result = estimate([], matrix, 60);
      expect(result.totalMinutes).toBe(0);
      expect(result.dayCountFlag).toBe(1);
    });

    it('sums travel time between consecutive stops + dwell time', () => {
      const stops = [
        makePoi('a', 0, 0, 15),
        makePoi('b', 0, 1, 20),
        makePoi('c', 0, 2, 10),
      ];
      const matrix: DurationMatrix = {
        points: stops.map((p) => p.location),
        mode: 'walking',
        durationsMinutes: [
          [0, 10, 25],
          [10, 0, 15],
          [25, 15, 0],
        ],
        distancesMeters: [
          [0, 500, 1200],
          [500, 0, 700],
          [1200, 700, 0],
        ],
      };

      // Travel: a→b(10) + b→c(15) = 25.
      // Dwell: 15 + 20 + 10 = 45.
      // Total: 70.
      const result = estimate(stops, matrix, 120);
      expect(result.totalMinutes).toBe(70);
      expect(result.dayCountFlag).toBe(1);
    });

    it('sets dayCountFlag > 1 when total exceeds budget', () => {
      const stops = [
        makePoi('a', 0, 0, 60),
        makePoi('b', 0, 1, 60),
      ];
      const matrix: DurationMatrix = {
        points: stops.map((p) => p.location),
        mode: 'walking',
        durationsMinutes: [
          [0, 30],
          [30, 0],
        ],
        distancesMeters: [
          [0, 1500],
          [1500, 0],
        ],
      };

      // Total = 30 (travel) + 120 (dwell) = 150.
      // Budget = 60 → dayCountFlag = ceil(150/60) = 3.
      const result = estimate(stops, matrix, 60);
      expect(result.totalMinutes).toBe(150);
      expect(result.dayCountFlag).toBe(3);
    });

    it('uses isochrone polygon to set dayCountFlag when POIs are outside', () => {
      const stops = [
        makePoi('a', 0, 0, 10),
        makePoi('b', 10, 10, 10), // Far outside the isochrone.
      ];
      const matrix: DurationMatrix = {
        points: stops.map((p) => p.location),
        mode: 'walking',
        durationsMinutes: [
          [0, 5],
          [5, 0],
        ],
        distancesMeters: [
          [0, 500],
          [500, 0],
        ],
      };

      // Total = 5 + 20 = 25 (fits in 60 min budget).
      // But POI 'b' at (10,10) is outside the isochrone polygon around (0,0).
      const isochrone = {
        center: { lat: 0, lng: 0 },
        timeBudgetMinutes: 60,
        mode: 'walking' as const,
        polygon: {
          type: 'Polygon' as const,
          coordinates: [
            [
              [-1, -1],
              [1, -1],
              [1, 1],
              [-1, 1],
              [-1, -1],
            ],
          ],
        },
      };

      const result = estimate(stops, matrix, 60, isochrone);
      expect(result.dayCountFlag).toBeGreaterThanOrEqual(2);
    });
  });

  describe('pointInPolygon', () => {
    const square: GeoJsonPolygon = {
      type: 'Polygon',
      coordinates: [
        [
          [0, 0],
          [10, 0],
          [10, 10],
          [0, 10],
          [0, 0],
        ],
      ],
    };

    it('returns true for a point inside the polygon', () => {
      expect(pointInPolygon({ lat: 5, lng: 5 }, square)).toBe(true);
    });

    it('returns false for a point outside the polygon', () => {
      expect(pointInPolygon({ lat: 15, lng: 15 }, square)).toBe(false);
    });

    it('returns false for an empty polygon', () => {
      const empty: GeoJsonPolygon = { type: 'Polygon', coordinates: [] };
      expect(pointInPolygon({ lat: 5, lng: 5 }, empty)).toBe(false);
    });
  });
});
