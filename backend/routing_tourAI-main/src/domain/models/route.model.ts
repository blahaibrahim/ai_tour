import type { Coordinate } from './coordinate.model.js';
import type { Segment } from './segment.model.js';

/**
 * Route-level transport descriptor. Includes 'hybrid' — unlike LegMode
 * (routing.model.ts), which only ever describes a single leg. Matches
 * the `transport_mode` enum on the `routes` table (Section 7).
 */
export type TransportMode = 'walking' | 'driving' | 'hybrid';

/**
 * One stop in the final assembled route — the shape the separate AR
 * trigger service consumes (Section 8: "ordered waypoints and a per-POI
 * checkpoint radius"). Mirrors `route_stops` (Section 7) plus the
 * checkpoint radius carried on Poi.
 */
export interface Waypoint {
  poiId: string;
  sequenceOrder: number;
  clusterId: number;
  location: Coordinate;
  checkpointRadiusMeters: number;
}

/**
 * Output of ResponseAssembler.assemble (Section 7). This is the
 * in-memory/DTO shape at assembly time — it has no database `id` or
 * `generatedAt` yet, which Route Repository assigns when it persists
 * this into the `routes` + `route_stops` tables.
 */
export interface RouteResponse {
  cityId: string;
  theme: string;
  timeBudgetMinutes: number;
  transportMode: TransportMode;
  segments: Segment[];
  waypoints: Waypoint[];
  estimatedTotalDurationMinutes: number;
  /** 1 = fits in one day; 2+ = rally needs multiple days (Section 5/8). */
  dayCountFlag: number;
}

/** A route as persisted and read back from the `routes` table. */
export interface PersistedRoute extends RouteResponse {
  id: string;
  sessionId: string | null;
  userId: string | null;
  generatedAt: Date;
}
