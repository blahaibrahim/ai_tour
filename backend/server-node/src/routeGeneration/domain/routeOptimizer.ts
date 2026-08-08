/**
 * Layer 3 — Route Optimizer.
 *
 * Orders clusters (driving) and orders the stops inside a cluster (walking).
 * Runs entirely in-memory against the cached duration matrix — it never calls
 * the routing provider itself.
 *
 * STATUS: stubs. Needs the Adapter's matrix call (spec §9 step 4).
 *
 * Algorithm, as specified (spec §5): nearest-neighbour construction followed
 * by a single 2-opt improvement pass. That lands within roughly 5% of optimal
 * for the stop counts involved — single digits to low teens per cluster — in
 * well under a millisecond. An exact TSP solver is deliberately not used: it
 * costs exponentially more for a gain no user would perceive.
 *
 * Worth keeping in view while implementing: the ordering itself costs under
 * 1 ms, and the two external calls dominate the latency budget entirely. There
 * is no version of this file that is worth optimizing further, and no version
 * of it that will make a request fast. Caching is the lever (spec §4).
 *
 * The matrix is indexed by position, so every function here takes the matrix
 * plus the points it was built from. Indexing it by anything derived from the
 * POI list — array position at call time, or object identity — is how the two
 * fall out of step.
 */
import { NotImplementedError } from "../errors";
import { Cluster, DurationMatrix, Poi } from "../types";

/** Spec §7, transcribed: `RouteOptimizer.orderClusters(clusters, matrix)`. */
export function orderClusters(_clusters: Cluster[], _matrix: DurationMatrix): Cluster[] {
  throw new NotImplementedError("RouteOptimizer.orderClusters");
}

/** Spec §7, transcribed: `RouteOptimizer.orderStopsWithinCluster(cluster, matrix)`. */
export function orderStopsWithinCluster(_cluster: Cluster, _matrix: DurationMatrix): Poi[] {
  throw new NotImplementedError("RouteOptimizer.orderStopsWithinCluster");
}

/**
 * Nearest-neighbour construction over a duration matrix, returning indices.
 *
 * Shared by both ordering functions above — the two differ only in what they
 * are ordering and which profile's matrix they were handed, not in the
 * algorithm.
 */
export function nearestNeighbourOrder(
  _matrix: DurationMatrix,
  _indices: number[],
  _startIndex: number,
): number[] {
  throw new NotImplementedError("RouteOptimizer.nearestNeighbourOrder");
}

/**
 * One 2-opt improvement pass: repeatedly reverse the segment between two
 * positions when doing so shortens the tour, until no single reversal helps.
 *
 * "A single pass" in the spec means one pass to convergence, not one candidate
 * swap — the 5%-of-optimal figure assumes the former.
 */
export function twoOptPass(_matrix: DurationMatrix, _order: number[]): number[] {
  throw new NotImplementedError("RouteOptimizer.twoOptPass");
}
