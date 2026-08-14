import { describe, it, expect } from 'vitest';
import {
  orderClusters,
  orderStopsWithinCluster,
} from '../../src/domain/services/route-optimizer/route-optimizer.js';
import type { Cluster } from '../../src/domain/models/cluster.model.js';
import type { Poi } from '../../src/domain/models/poi.model.js';
import type { DurationMatrix } from '../../src/domain/models/routing.model.js';

function makePoi(id: string, lat: number, lng: number): Poi {
  return {
    id,
    cityId: 'city-1',
    categoryId: 'cat-1',
    nameFr: null,
    nameAr: null,
    nameEn: null,
    location: { lat, lng },
    openingHoursRaw: null,
    avgVisitDurationMinutes: 15,
    checkpointRadiusMeters: 30,
  };
}

function makeCluster(id: number, pois: Poi[]): Cluster {
  return {
    id,
    pois,
    anchor: {
      lat: pois.reduce((s, p) => s + p.location.lat, 0) / pois.length,
      lng: pois.reduce((s, p) => s + p.location.lng, 0) / pois.length,
    },
  };
}

describe('RouteOptimizer', () => {
  describe('orderClusters', () => {
    it('returns the same single cluster untouched', () => {
      const c = makeCluster(0, [makePoi('a', 36.0, 3.0)]);
      const matrix: DurationMatrix = {
        points: [c.anchor],
        mode: 'driving',
        durationsMinutes: [[0]],
        distancesMeters: [[0]],
      };
      const result = orderClusters([c], matrix);
      expect(result).toHaveLength(1);
      expect(result[0]!.id).toBe(0);
    });

    it('reorders clusters to minimize driving duration', () => {
      // 3 clusters with an asymmetric matrix:
      //   0→1=10, 0→2=20, 1→2=5, 2→0=20, 2→1=15, 1→0=10
      // Best order from 0: 0 → 1 → 2 (total = 10 + 5 = 15)
      // vs 0 → 2 → 1 (total = 20 + 15 = 35)
      const clusters = [
        makeCluster(0, [makePoi('a', 36.0, 3.0)]),
        makeCluster(1, [makePoi('b', 36.1, 3.1)]),
        makeCluster(2, [makePoi('c', 36.2, 3.2)]),
      ];
      const matrix: DurationMatrix = {
        points: clusters.map((c) => c.anchor),
        mode: 'driving',
        durationsMinutes: [
          [0, 10, 20],
          [10, 0, 5],
          [20, 15, 0],
        ],
        distancesMeters: [
          [0, 1000, 2000],
          [1000, 0, 500],
          [2000, 1500, 0],
        ],
      };

      const result = orderClusters(clusters, matrix);

      // NN starting from 0 → picks 1 (cost 10), then 2 (cost 5).
      expect(result.map((c) => c.id)).toEqual([0, 1, 2]);
    });
  });

  describe('orderStopsWithinCluster', () => {
    it('returns a single POI untouched', () => {
      const poi = makePoi('a', 36.0, 3.0);
      const cluster = makeCluster(0, [poi]);
      const matrix: DurationMatrix = {
        points: [poi.location],
        mode: 'walking',
        durationsMinutes: [[0]],
        distancesMeters: [[0]],
      };
      const result = orderStopsWithinCluster(cluster, matrix);
      expect(result).toHaveLength(1);
      expect(result[0]!.id).toBe('a');
    });

    it('reorders stops to minimize walking duration', () => {
      // 3 stops with matrix that makes 0→2→1 cheaper than 0→1→2.
      //   0→1=20, 0→2=5, 1→2=3
      const pois = [makePoi('a', 0, 0), makePoi('b', 0, 1), makePoi('c', 0, 2)];
      const cluster = makeCluster(0, pois);
      const matrix: DurationMatrix = {
        points: pois.map((p) => p.location),
        mode: 'walking',
        durationsMinutes: [
          [0, 20, 5],
          [20, 0, 3],
          [5, 3, 0],
        ],
        distancesMeters: [
          [0, 2000, 500],
          [2000, 0, 300],
          [500, 300, 0],
        ],
      };

      const result = orderStopsWithinCluster(cluster, matrix);

      // NN: start at 0, pick 2 (cost 5), then 1 (cost 3). Total = 8.
      // vs 0→1 (20) + 1→2 (3) = 23.
      expect(result.map((p) => p.id)).toEqual(['a', 'c', 'b']);
    });
  });
});
