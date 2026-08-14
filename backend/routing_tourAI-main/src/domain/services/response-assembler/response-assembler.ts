import type { Cluster } from '../../models/cluster.model.js';
import type { Poi } from '../../models/poi.model.js';
import type { RouteResponse, TransportMode, Waypoint } from '../../models/route.model.js';
import type { Segment } from '../../models/segment.model.js';
import type { TimeEstimate } from '../time-reachability-estimator/time-reachability-estimator.js';

export interface AssembleInput {
  orderedClusters: Cluster[];
  segments: Segment[];
  estimate: TimeEstimate;
  cityId: string;
  theme: string;
  timeBudgetMinutes: number;
}

/**
 * Response Assembler (Section 3): builds the final route object with
 * segments, mode tags, and checkpoint radii. Pure function — takes
 * fully-computed data and shapes it into the RouteResponse DTO.
 *
 * Section 5: "Every output segment is tagged with its mode (drive /
 * walk) — this tagging is what lets the AR/UI layer render 'drive here,
 * then walk this loop' without knowing how the segment was generated."
 */
export function assemble(input: AssembleInput): RouteResponse {
  const { orderedClusters, segments, estimate, cityId, theme, timeBudgetMinutes } = input;

  // Derive transport mode from segments present.
  const transportMode = deriveTransportMode(segments);

  // Build waypoints from ordered clusters — the shape the AR trigger
  // service consumes (Section 8).
  const waypoints: Waypoint[] = [];
  let sequenceOrder = 0;

  for (const cluster of orderedClusters) {
    for (const poi of cluster.pois) {
      waypoints.push({
        poiId: poi.id,
        sequenceOrder,
        clusterId: cluster.id,
        location: poi.location,
        checkpointRadiusMeters: poi.checkpointRadiusMeters,
      });
      sequenceOrder++;
    }
  }

  return {
    cityId,
    theme,
    timeBudgetMinutes,
    transportMode,
    segments,
    waypoints,
    estimatedTotalDurationMinutes: Math.round(estimate.totalMinutes),
    dayCountFlag: estimate.dayCountFlag,
  };
}

/**
 * Derive the route-level TransportMode from the set of segment modes.
 * If segments contain both driving and walking, it's 'hybrid'. If only
 * one type, use that. Falls back to 'hybrid' if no segments.
 */
function deriveTransportMode(segments: Segment[]): TransportMode {
  const hasWalking = segments.some((s) => s.mode === 'walking');
  const hasDriving = segments.some((s) => s.mode === 'driving');

  if (hasWalking && hasDriving) return 'hybrid';
  if (hasWalking) return 'walking';
  if (hasDriving) return 'driving';
  return 'hybrid';
}
