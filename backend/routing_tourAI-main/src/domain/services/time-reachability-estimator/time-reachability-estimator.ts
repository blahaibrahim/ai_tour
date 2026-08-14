import type { Coordinate, GeoJsonPolygon } from '../../models/coordinate.model.js';
import type { Poi } from '../../models/poi.model.js';
import type { DurationMatrix, IsochronePolygon } from '../../models/routing.model.js';

export interface TimeEstimate {
  totalMinutes: number;
  dayCountFlag: number;
}

/**
 * Time & Reachability Estimator (Section 3/5):
 *   Total duration = Σ travel-time segments + Σ per-POI dwell time.
 *   Day-count flag = 1 if all POIs fit within the time budget;
 *                    2+ if remaining unvisited POIs fall outside the
 *                    reachable isochrone for the remaining time.
 */

/**
 * Estimate total route duration and determine whether the trip needs
 * multiple days.
 *
 * @param orderedStops  POIs in visit order (flattened across clusters).
 * @param matrix        Duration matrix covering all stops (indices must
 *                      match the orderedStops array).
 * @param timeBudgetMinutes  The user's stated time budget.
 * @param isochrone     Optional isochrone polygon for reachability check.
 *                      If provided and some POIs fall outside, dayCountFlag > 1.
 */
export function estimate(
  orderedStops: Poi[],
  matrix: DurationMatrix,
  timeBudgetMinutes: number,
  isochrone?: IsochronePolygon | null,
): TimeEstimate {
  if (orderedStops.length === 0) {
    return { totalMinutes: 0, dayCountFlag: 1 };
  }

  // Sum travel time between consecutive stops.
  let travelMinutes = 0;
  for (let i = 0; i < orderedStops.length - 1; i++) {
    travelMinutes += matrix.durationsMinutes[i]?.[i + 1] ?? 0;
  }

  // Sum dwell time.
  let dwellMinutes = 0;
  for (const stop of orderedStops) {
    dwellMinutes += stop.avgVisitDurationMinutes;
  }

  const totalMinutes = travelMinutes + dwellMinutes;

  // Day-count flag: if total exceeds the budget, check isochrone.
  let dayCountFlag = 1;
  if (totalMinutes > timeBudgetMinutes) {
    dayCountFlag = Math.ceil(totalMinutes / timeBudgetMinutes);
  }

  // Isochrone-based refinement: if we have an isochrone polygon,
  // check whether any stops fall outside it.
  if (isochrone) {
    const outsideCount = orderedStops.filter(
      (stop) => !pointInPolygon(stop.location, isochrone.polygon),
    ).length;

    if (outsideCount > 0 && dayCountFlag < 2) {
      dayCountFlag = 2;
    }
  }

  return { totalMinutes, dayCountFlag };
}

// ---------------------------------------------------------------------------
// Ray-casting point-in-polygon test (Section 5: isochrone check). Works
// with GeoJSON Polygon geometry (exterior ring only; holes ignored for
// this use case). Pure TypeScript, no external dependency.
// ---------------------------------------------------------------------------

/**
 * Tests whether a point (lat/lng) falls inside a GeoJSON Polygon.
 * Coordinates in GeoJSON are [lng, lat] — the conversion is handled
 * here so callers pass the domain Coordinate shape.
 */
export function pointInPolygon(point: Coordinate, polygon: GeoJsonPolygon): boolean {
  const exteriorRing = polygon.coordinates[0];
  if (!exteriorRing || exteriorRing.length === 0) return false;

  // Ray-casting algorithm against the exterior ring.
  const px = point.lng;
  const py = point.lat;
  let inside = false;

  for (let i = 0, j = exteriorRing.length - 1; i < exteriorRing.length; j = i++) {
    const xi = exteriorRing[i]![0]!; // lng
    const yi = exteriorRing[i]![1]!; // lat
    const xj = exteriorRing[j]![0]!; // lng
    const yj = exteriorRing[j]![1]!; // lat

    const intersect =
      yi > py !== yj > py && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi;

    if (intersect) inside = !inside;
  }

  return inside;
}
