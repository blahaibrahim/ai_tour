import type { Coordinate } from './coordinate.model.js';
import type { LegMode } from './routing.model.js';

/**
 * One leg of an assembled route. Section 5: "Every output segment is
 * tagged with its mode (drive / walk) — this tagging is what lets the
 * AR/UI layer render 'drive here, then walk this loop' without knowing
 * how the segment was generated."
 *
 * fromPoiId/toPoiId are null when a segment's endpoint is a cluster
 * anchor rather than a specific POI (e.g. the inter-cluster drive before
 * any POI in the destination cluster has been chosen).
 */
export interface Segment {
  mode: LegMode;
  from: Coordinate;
  to: Coordinate;
  fromPoiId: string | null;
  toPoiId: string | null;
  durationMinutes: number;
  distanceMeters: number;
  geometry: Coordinate[];
}
