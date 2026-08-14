import type { Cluster } from '../../models/cluster.model.js';
import type { Poi } from '../../models/poi.model.js';
import type { DurationMatrix } from '../../models/routing.model.js';

/**
 * Route Optimizer (Section 3/5): orders clusters (driving) and stops
 * within a cluster (walking). Uses Nearest-Neighbor construction
 * followed by a single 2-opt improvement pass, run entirely in-memory
 * against the cached distance/duration matrix.
 *
 * "This gives a route within roughly 5% of optimal for the stop counts
 * involved (single digits to low teens per cluster) in well under a
 * millisecond." — Section 5
 */

/**
 * Orders clusters by driving duration using the matrix of cluster
 * anchors. Matrix indices must correspond 1-to-1 with the `clusters`
 * array.
 */
export function orderClusters(
  clusters: Cluster[],
  matrix: DurationMatrix,
): Cluster[] {
  if (clusters.length <= 1) return clusters;

  const order = nearestNeighborOrder(clusters.length, matrix.durationsMinutes);
  const improved = twoOptImprove(order, matrix.durationsMinutes);
  return improved.map((i) => clusters[i]!);
}

/**
 * Orders POIs within a single cluster for walking. Matrix indices must
 * correspond 1-to-1 with `cluster.pois`.
 */
export function orderStopsWithinCluster(
  cluster: Cluster,
  matrix: DurationMatrix,
): Poi[] {
  if (cluster.pois.length <= 1) return cluster.pois;

  const order = nearestNeighborOrder(cluster.pois.length, matrix.durationsMinutes);
  const improved = twoOptImprove(order, matrix.durationsMinutes);
  return improved.map((i) => cluster.pois[i]!);
}

// ---------------------------------------------------------------------------
// Nearest-Neighbor heuristic: start at index 0, greedily pick the closest
// unvisited node at each step.
// ---------------------------------------------------------------------------

function nearestNeighborOrder(n: number, durations: number[][]): number[] {
  const visited = new Set<number>();
  const order: number[] = [];
  let current = 0;

  visited.add(current);
  order.push(current);

  while (order.length < n) {
    let bestNext = -1;
    let bestDuration = Infinity;

    for (let j = 0; j < n; j++) {
      if (visited.has(j)) continue;
      const d = durations[current]?.[j] ?? Infinity;
      if (d < bestDuration) {
        bestDuration = d;
        bestNext = j;
      }
    }

    if (bestNext === -1) break;
    visited.add(bestNext);
    order.push(bestNext);
    current = bestNext;
  }

  return order;
}

// ---------------------------------------------------------------------------
// 2-opt local search: repeatedly reverse sub-sequences if doing so
// shortens the total path. Runs one full pass over all (i,j) pairs.
// ---------------------------------------------------------------------------

function twoOptImprove(order: number[], durations: number[][]): number[] {
  const route = [...order];
  const n = route.length;
  let improved = true;

  while (improved) {
    improved = false;
    for (let i = 0; i < n - 1; i++) {
      for (let j = i + 2; j < n; j++) {
        const delta = twoOptDelta(route, durations, i, j);
        if (delta < -1e-9) {
          // Reverse the segment between i+1 and j (inclusive).
          reverse(route, i + 1, j);
          improved = true;
        }
      }
    }
  }

  return route;
}

/**
 * Computes the change in total distance if we reverse the sub-path
 * route[i+1..j]. Only considers the two edges that change:
 *   old: route[i]→route[i+1] + route[j]→route[j+1]
 *   new: route[i]→route[j]   + route[i+1]→route[j+1]
 * For the last node (j === n-1) there is no route[j+1] edge.
 */
function twoOptDelta(
  route: number[],
  durations: number[][],
  i: number,
  j: number,
): number {
  const n = route.length;
  const a = route[i]!;
  const b = route[i + 1]!;
  const c = route[j]!;

  const oldAB = durations[a]?.[b] ?? 0;
  const newAC = durations[a]?.[c] ?? 0;

  if (j === n - 1) {
    // Open path: only one edge changes.
    return newAC - oldAB;
  }

  const d = route[j + 1]!;
  const oldCD = durations[c]?.[d] ?? 0;
  const newBD = durations[b]?.[d] ?? 0;

  return (newAC + newBD) - (oldAB + oldCD);
}

function reverse(arr: number[], from: number, to: number): void {
  let left = from;
  let right = to;
  while (left < right) {
    const tmp = arr[left]!;
    arr[left] = arr[right]!;
    arr[right] = tmp;
    left++;
    right--;
  }
}
