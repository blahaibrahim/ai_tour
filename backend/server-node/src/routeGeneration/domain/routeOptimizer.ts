/**
 * Layer 3 — Route Optimizer.
 *
 * Orders clusters (driving) and orders the stops inside a cluster (walking).
 * Runs entirely in-memory against the cached duration matrix — it never calls
 * the routing provider itself.
 *
 * Algorithm, as specified (spec §5): nearest-neighbour construction followed
 * by a single 2-opt improvement pass. That lands within roughly 5% of optimal
 * for the stop counts involved — single digits to low teens per cluster — in
 * well under a millisecond. An exact TSP solver is deliberately not used: it
 * costs exponentially more for a gain no user would perceive.
 *
 * Worth keeping in view: the ordering itself costs under 1 ms, and the two
 * external calls dominate the latency budget entirely. There is no version of
 * this file that is worth optimizing further, and no version of it that will
 * make a request fast. Caching is the lever (spec §4).
 *
 * ## Matrix indexing
 *
 * The matrix is indexed by position in the `points` array it was built from,
 * which is *not* the order the clusters or stops are in by the time they reach
 * here — `orderClusters` returns a permutation, and the caller then asks for
 * stop ordering against a matrix built before that permutation existed.
 *
 * So nothing here indexes by array position or object identity. Every lookup
 * goes through `indexPoints`, which maps a coordinate back to its row in the
 * matrix. This is the failure the original stub warned about, and it is a
 * quiet one: mismatched indices produce a route that is ordered, plausible,
 * and wrong.
 */
import { Cluster, Coordinate, DurationMatrix, Poi } from "../types";

/** Coordinates round-trip through JSON, so identity is not a key — the value
 * is. Seven decimal places is ~11 mm, far below any positional ambiguity. */
function coordKey(c: Coordinate): string {
  return `${c.lat.toFixed(7)},${c.lng.toFixed(7)}`;
}

/** Maps every point in the matrix to its row index. */
function indexPoints(matrix: DurationMatrix): Map<string, number> {
  const index = new Map<string, number>();
  matrix.points.forEach((p, i) => {
    // First wins: duplicate coordinates (two POIs at one address) would
    // otherwise make the later one shadow the earlier, and either row is
    // equally correct for a pair that is zero metres apart.
    if (!index.has(coordKey(p))) index.set(coordKey(p), i);
  });
  return index;
}

/**
 * Travel seconds between two matrix rows.
 *
 * `null` in the matrix means the provider found the pair unroutable. Treated
 * as "very expensive but not impossible" rather than Infinity, so an
 * unroutable pair sinks to the end of the ordering instead of poisoning every
 * comparison it appears in and making the whole tour arbitrary.
 */
const UNROUTABLE_PENALTY_SECONDS = 6 * 60 * 60;

function cost(matrix: DurationMatrix, from: number, to: number): number {
  const value = matrix.durations[from]?.[to];
  return typeof value === "number" ? value : UNROUTABLE_PENALTY_SECONDS;
}

/** Spec §7, transcribed: `RouteOptimizer.orderClusters(clusters, matrix)`. */
export function orderClusters(clusters: Cluster[], matrix: DurationMatrix): Cluster[] {
  if (clusters.length <= 1) return clusters;

  const index = indexPoints(matrix);
  const rows = clusters.map((c) => index.get(coordKey(c.anchor)));
  // A cluster whose anchor is not in this matrix cannot be ordered against the
  // others. Rather than guess, leave the input order alone — it is at least
  // the order the clustering produced, and a wrong ordering is worse than an
  // unoptimised one.
  if (rows.some((r) => r === undefined)) return clusters;

  const byRow = new Map<number, Cluster>();
  rows.forEach((r, i) => byRow.set(r!, clusters[i]!));

  const order = twoOptPass(matrix, nearestNeighbourOrder(matrix, rows as number[], rows[0]!));
  return order.map((row) => byRow.get(row)!);
}

/** Spec §7, transcribed: `RouteOptimizer.orderStopsWithinCluster(cluster, matrix)`. */
export function orderStopsWithinCluster(cluster: Cluster, matrix: DurationMatrix): Poi[] {
  if (cluster.pois.length <= 1) return cluster.pois;

  const index = indexPoints(matrix);
  const rows = cluster.pois.map((p) => index.get(coordKey(p.location)));
  if (rows.some((r) => r === undefined)) return cluster.pois;

  const byRow = new Map<number, Poi>();
  rows.forEach((r, i) => byRow.set(r!, cluster.pois[i]!));

  // Starts at the stop nearest the anchor: the traveller arrives at the anchor
  // by car, so the walking loop should begin where they parked rather than at
  // whichever stop happened to be first in the array.
  const anchorRow = index.get(coordKey(cluster.anchor));
  const start =
    anchorRow !== undefined && rows.includes(anchorRow)
      ? anchorRow
      : nearestRow(matrix, rows as number[], anchorRow) ?? rows[0]!;

  const order = twoOptPass(matrix, nearestNeighbourOrder(matrix, rows as number[], start));
  return order.map((row) => byRow.get(row)!);
}

function nearestRow(
  matrix: DurationMatrix,
  candidates: number[],
  from: number | undefined,
): number | undefined {
  if (from === undefined) return undefined;
  let best: number | undefined;
  let bestCost = Infinity;
  for (const row of candidates) {
    const c = cost(matrix, from, row);
    if (c < bestCost) {
      bestCost = c;
      best = row;
    }
  }
  return best;
}

/**
 * Nearest-neighbour construction over a duration matrix, returning indices.
 *
 * Shared by both ordering functions above — the two differ only in what they
 * are ordering and which profile's matrix they were handed, not in the
 * algorithm.
 */
export function nearestNeighbourOrder(
  matrix: DurationMatrix,
  indices: number[],
  startIndex: number,
): number[] {
  if (indices.length === 0) return [];

  const remaining = new Set(indices);
  const start = remaining.has(startIndex) ? startIndex : indices[0]!;

  const order: number[] = [start];
  remaining.delete(start);
  let current = start;

  while (remaining.size > 0) {
    let next = -1;
    let bestCost = Infinity;
    for (const candidate of remaining) {
      const c = cost(matrix, current, candidate);
      if (c < bestCost) {
        bestCost = c;
        next = candidate;
      }
    }
    if (next === -1) break;
    order.push(next);
    remaining.delete(next);
    current = next;
  }

  return order;
}

/**
 * One 2-opt improvement pass: repeatedly reverse the segment between two
 * positions when doing so shortens the tour, until no single reversal helps.
 *
 * "A single pass" in the spec means one pass to convergence, not one candidate
 * swap — the 5%-of-optimal figure assumes the former.
 *
 * This is an *open* path, not a closed tour: the traveller does not return to
 * the first stop, so the edge from the last stop back to the first must not be
 * counted. Treating it as closed is the classic way to get a route that
 * doubles back for no visible reason.
 */
export function twoOptPass(matrix: DurationMatrix, order: number[]): number[] {
  const route = [...order];
  const n = route.length;
  if (n < 4) return route;

  // Bounded because a pathological matrix (many equal costs, floating-point
  // ties) can otherwise oscillate between two equally good tours forever.
  const MAX_ROUNDS = 32;

  for (let round = 0; round < MAX_ROUNDS; round++) {
    let improved = false;

    for (let i = 0; i < n - 2; i++) {
      for (let j = i + 2; j < n; j++) {
        const a = route[i]!;
        const b = route[i + 1]!;
        const c = route[j]!;

        const before = cost(matrix, a, b);
        const after = cost(matrix, a, c);

        // The trailing edge only exists when j is not the last stop — the open
        // path has no edge after route[n-1].
        const trailingBefore = j === n - 1 ? 0 : cost(matrix, c, route[j + 1]!);
        const trailingAfter = j === n - 1 ? 0 : cost(matrix, b, route[j + 1]!);

        const delta = after + trailingAfter - (before + trailingBefore);
        if (delta < -1e-9) {
          reverse(route, i + 1, j);
          improved = true;
        }
      }
    }

    if (!improved) break;
  }

  return route;
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
