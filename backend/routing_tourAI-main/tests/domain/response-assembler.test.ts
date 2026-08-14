import { describe, it, expect } from 'vitest';
import { assemble } from '../../src/domain/services/response-assembler/response-assembler.js';
import type { Cluster } from '../../src/domain/models/cluster.model.js';
import type { Poi } from '../../src/domain/models/poi.model.js';
import type { Segment } from '../../src/domain/models/segment.model.js';

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

describe('ResponseAssembler', () => {
  it('builds a correct RouteResponse with waypoints and mode tags', () => {
    const pois = [
      makePoi('a', 36.0, 3.0),
      makePoi('b', 36.01, 3.01),
      makePoi('c', 37.0, 4.0),
    ];

    const clusters: Cluster[] = [
      { id: 0, pois: [pois[0]!, pois[1]!], anchor: { lat: 36.005, lng: 3.005 } },
      { id: 1, pois: [pois[2]!], anchor: { lat: 37.0, lng: 4.0 } },
    ];

    const segments: Segment[] = [
      {
        mode: 'walking',
        from: pois[0]!.location,
        to: pois[1]!.location,
        fromPoiId: 'a',
        toPoiId: 'b',
        durationMinutes: 5,
        distanceMeters: 400,
        geometry: [pois[0]!.location, pois[1]!.location],
      },
      {
        mode: 'driving',
        from: clusters[0]!.anchor,
        to: clusters[1]!.anchor,
        fromPoiId: null,
        toPoiId: null,
        durationMinutes: 20,
        distanceMeters: 15000,
        geometry: [clusters[0]!.anchor, clusters[1]!.anchor],
      },
    ];

    const result = assemble({
      orderedClusters: clusters,
      segments,
      estimate: { totalMinutes: 55, dayCountFlag: 1 },
      cityId: 'city-1',
      theme: 'heritage',
      timeBudgetMinutes: 120,
    });

    expect(result.transportMode).toBe('hybrid');
    expect(result.estimatedTotalDurationMinutes).toBe(55);
    expect(result.dayCountFlag).toBe(1);
    expect(result.segments).toHaveLength(2);
    expect(result.waypoints).toHaveLength(3);

    // Verify waypoint ordering.
    expect(result.waypoints[0]!.poiId).toBe('a');
    expect(result.waypoints[0]!.sequenceOrder).toBe(0);
    expect(result.waypoints[0]!.clusterId).toBe(0);

    expect(result.waypoints[1]!.poiId).toBe('b');
    expect(result.waypoints[1]!.sequenceOrder).toBe(1);
    expect(result.waypoints[1]!.clusterId).toBe(0);

    expect(result.waypoints[2]!.poiId).toBe('c');
    expect(result.waypoints[2]!.sequenceOrder).toBe(2);
    expect(result.waypoints[2]!.clusterId).toBe(1);
  });

  it('derives transportMode as walking when all segments are walking', () => {
    const poi = makePoi('a', 36.0, 3.0);
    const cluster: Cluster = { id: 0, pois: [poi], anchor: poi.location };

    const result = assemble({
      orderedClusters: [cluster],
      segments: [
        {
          mode: 'walking',
          from: poi.location,
          to: poi.location,
          fromPoiId: 'a',
          toPoiId: 'a',
          durationMinutes: 0,
          distanceMeters: 0,
          geometry: [],
        },
      ],
      estimate: { totalMinutes: 15, dayCountFlag: 1 },
      cityId: 'city-1',
      theme: 'nature',
      timeBudgetMinutes: 60,
    });

    expect(result.transportMode).toBe('walking');
  });

  it('includes per-POI checkpoint radius in waypoints', () => {
    const poi = { ...makePoi('x', 0, 0), checkpointRadiusMeters: 42 };
    const cluster: Cluster = { id: 0, pois: [poi], anchor: poi.location };

    const result = assemble({
      orderedClusters: [cluster],
      segments: [],
      estimate: { totalMinutes: 15, dayCountFlag: 1 },
      cityId: 'city-1',
      theme: 'all',
      timeBudgetMinutes: 30,
    });

    expect(result.waypoints[0]!.checkpointRadiusMeters).toBe(42);
  });
});
