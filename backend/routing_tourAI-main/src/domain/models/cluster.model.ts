import type { Coordinate } from './coordinate.model.js';
import type { Poi } from './poi.model.js';

/**
 * A walkable grouping of POIs produced by the Clustering Engine
 * (Section 5's fixed-radius greedy grouping). `id` matches
 * `route_stops.cluster_id` (Section 7) once persisted.
 */
export interface Cluster {
  id: number;
  pois: Poi[];
  /**
   * Single representative point used for inter-cluster driving legs
   * (Section 5: "driving profile, anchor point to anchor point"). Route
   * Optimizer treats clusters as atomic points when ordering them;
   * intra-cluster walking order is decided separately, after arrival.
   */
  anchor: Coordinate;
}
