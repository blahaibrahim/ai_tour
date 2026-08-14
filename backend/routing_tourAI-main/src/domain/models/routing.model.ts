import type { Coordinate, GeoJsonPolygon } from './coordinate.model.js';

/**
 * The two leg-level transport profiles a routing provider call can be
 * made for. Distinct from `TransportMode` (route.model.ts), which adds
 * 'hybrid' — a route-level composite, never a single leg's mode.
 */
export type LegMode = 'walking' | 'driving';

/** Result of RoutingProviderAdapter.getRoute (Section 7). */
export interface RouteResult {
  mode: LegMode;
  durationMinutes: number;
  distanceMeters: number;
  /** Ordered path geometry for this leg, for map rendering. */
  geometry: Coordinate[];
}

/**
 * Result of RoutingProviderAdapter.getMatrix (Section 7). Covers every
 * pair among `points` in one call — Section 4's efficiency rule: the
 * matrix endpoint is called once per request, never once per pair.
 *
 * durationsMinutes[i][j] is travel time from points[i] to points[j].
 * Indices exactly mirror the `points` array supplied to getMatrix, so
 * callers must keep their own index-to-entity mapping (e.g. cluster
 * anchors or POI list) alongside this matrix.
 */
export interface DurationMatrix {
  points: Coordinate[];
  mode: LegMode;
  durationsMinutes: number[][];
  distancesMeters: number[][];
}

/** Result of RoutingProviderAdapter.getIsochrone (Section 7). */
export interface IsochronePolygon {
  center: Coordinate;
  timeBudgetMinutes: number;
  mode: LegMode;
  polygon: GeoJsonPolygon;
}
