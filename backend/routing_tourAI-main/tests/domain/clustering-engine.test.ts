import { describe, it, expect } from 'vitest';
import { cluster, haversineMeters } from '../../src/domain/services/clustering-engine/clustering-engine.js';
import type { Poi } from '../../src/domain/models/poi.model.js';

function makePoi(overrides: Partial<Poi> & { id: string; location: Poi['location'] }): Poi {
  return {
    cityId: 'city-1',
    categoryId: 'cat-1',
    nameFr: null,
    nameAr: null,
    nameEn: null,
    openingHoursRaw: null,
    avgVisitDurationMinutes: 15,
    checkpointRadiusMeters: 30,
    ...overrides,
  };
}

describe('ClusteringEngine', () => {
  it('returns an empty array for zero POIs', () => {
    expect(cluster([], 500)).toEqual([]);
  });

  it('puts a single POI in its own cluster', () => {
    const pois = [makePoi({ id: 'a', location: { lat: 36.78, lng: 3.06 } })];
    const result = cluster(pois, 500);

    expect(result).toHaveLength(1);
    expect(result[0]!.pois).toHaveLength(1);
    expect(result[0]!.pois[0]!.id).toBe('a');
    expect(result[0]!.anchor).toEqual({ lat: 36.78, lng: 3.06 });
  });

  it('groups nearby POIs into one cluster', () => {
    // Two points ~200m apart in Algiers.
    const pois = [
      makePoi({ id: 'a', location: { lat: 36.7853, lng: 3.0588 } }),
      makePoi({ id: 'b', location: { lat: 36.7870, lng: 3.0560 } }),
    ];
    const result = cluster(pois, 500);

    expect(result).toHaveLength(1);
    expect(result[0]!.pois).toHaveLength(2);
  });

  it('separates distant POIs into different clusters', () => {
    // Casbah and Martyrs Memorial (~4.5km apart).
    const pois = [
      makePoi({ id: 'casbah', location: { lat: 36.7853, lng: 3.0588 } }),
      makePoi({ id: 'martyrs', location: { lat: 36.7470, lng: 3.0710 } }),
    ];
    const result = cluster(pois, 500);

    expect(result).toHaveLength(2);
    expect(result[0]!.pois).toHaveLength(1);
    expect(result[1]!.pois).toHaveLength(1);
  });

  it('assigns sequential cluster IDs starting from 0', () => {
    const pois = [
      makePoi({ id: 'a', location: { lat: 36.0, lng: 3.0 } }),
      makePoi({ id: 'b', location: { lat: 37.0, lng: 4.0 } }),
      makePoi({ id: 'c', location: { lat: 38.0, lng: 5.0 } }),
    ];
    const result = cluster(pois, 500);

    expect(result.map((c) => c.id)).toEqual([0, 1, 2]);
  });

  it('computes anchor as centroid of cluster members', () => {
    const pois = [
      makePoi({ id: 'a', location: { lat: 36.0, lng: 3.0 } }),
      makePoi({ id: 'b', location: { lat: 36.002, lng: 3.002 } }),
    ];
    // These are ~300m apart, so they'll cluster at radius 500m.
    const result = cluster(pois, 500);

    expect(result).toHaveLength(1);
    expect(result[0]!.anchor.lat).toBeCloseTo(36.001, 3);
    expect(result[0]!.anchor.lng).toBeCloseTo(3.001, 3);
  });
});

describe('haversineMeters', () => {
  it('returns 0 for identical points', () => {
    const p = { lat: 36.78, lng: 3.06 };
    expect(haversineMeters(p, p)).toBe(0);
  });

  it('returns a plausible distance for two Algiers landmarks', () => {
    // Casbah to Martyrs Memorial — roughly 4.4km.
    const casbah = { lat: 36.7853, lng: 3.0588 };
    const martyrs = { lat: 36.7470, lng: 3.0710 };
    const distance = haversineMeters(casbah, martyrs);

    expect(distance).toBeGreaterThan(4000);
    expect(distance).toBeLessThan(5000);
  });
});
