/**
 * Layer 3 — Time & Reachability Estimator.
 *
 * Sums travel and dwell time, and sets the day-count flag via an isochrone
 * check (spec §3).
 *
 * STATUS: stub. Built last of the domain components, because it is the only
 * one needing both the Adapter's isochrone call and the Data layer's dwell
 * times (spec §9 step 4).
 *
 * Specified arithmetic (spec §5):
 *
 *   totalDuration = Σ travel-time segments (from the cached matrix)
 *                 + Σ per-POI dwell time (from POI data)
 *
 *   dayCountFlag  = 2+ when an isochrone check says the remaining unvisited
 *                   POIs fall outside the area reachable in the remaining
 *                   time budget.
 *
 * Note what the day-count check is *not*: it is not `totalMinutes >
 * timeBudget`. It asks whether the leftover POIs are reachable at all in
 * what's left, which is a question about geography, not arithmetic — a stop
 * 40 minutes' drive away is unreachable in a 30-minute remainder however few
 * minutes of dwell time it needs.
 *
 * The isochrone call is the second of the two external calls in the budget,
 * and the reason the cold-cache ceiling is 1.5 s rather than 800 ms. It is
 * cached per (poi, time bucket, mode) — see `isochroneBucket` in the cache
 * adapter for why the budget is rounded before it becomes a key.
 */
import { NotImplementedError } from "../errors";
import { DurationMatrix, Poi, TimeEstimate } from "../types";

export interface EstimateInput {
  orderedStops: Poi[];
  matrix: DurationMatrix;
  /** Minutes per POI id. Sourced from `pois.avg_visit_duration_minutes`. */
  dwellTimes: Record<string, number>;
  /** The traveller's stated budget, for the reachability half. */
  timeBudgetMinutes: number;
}

/** Spec §7, transcribed: `TimeEstimator.estimate(...)`. */
export function estimate(_input: EstimateInput): Promise<TimeEstimate> {
  throw new NotImplementedError("TimeEstimator.estimate");
}

/**
 * The reachability half, separated because it is the only part that makes an
 * external call — keeping it apart means the arithmetic above stays a pure
 * function that can be unit-tested against a fixed matrix (spec §11).
 */
export function computeDayCountFlag(
  _orderedStops: Poi[],
  _matrix: DurationMatrix,
  _remainingBudgetMinutes: number,
): Promise<number> {
  throw new NotImplementedError("TimeEstimator.computeDayCountFlag");
}
