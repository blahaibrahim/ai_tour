/**
 * Layer 3 — Time & Reachability Estimator.
 *
 * Sums travel and dwell time, and sets the day-count flag via an isochrone
 * check (spec §3).
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
 * ## Deviation from the original stub: this layer stays pure
 *
 * The stub had `computeDayCountFlag` making the isochrone call itself. It
 * takes the already-fetched polygon instead, and the orchestrator does the
 * fetching — because spec §2/§3 specify Layer 3 as pure and Layer 2 as the
 * owner of provider access and graceful degradation. Keeping the call here
 * would have made the one component with real arithmetic in it the only one
 * that could not be unit-tested against a fixed input (spec §11).
 *
 * The polygon is optional. When it is absent — no key, provider down, cache
 * cold — the day count falls back to sequential packing, which is honest
 * about being the weaker answer rather than pretending the check ran.
 */
import { DurationMatrix, IsochronePolygon, Poi, TimeEstimate } from "../types";

export interface EstimateInput {
  orderedStops: Poi[];
  matrix: DurationMatrix;
  /** Minutes per POI id. Sourced from `pois.avg_visit_duration_minutes`. */
  dwellTimes: Record<string, number>;
  /** The traveller's stated budget, for the reachability half. */
  timeBudgetMinutes: number;
  /**
   * Reachable area from the first stop within the budget, if it could be
   * fetched. Absent means the geographic check is skipped, not that it passed.
   */
  isochrone?: IsochronePolygon | null;
}

const UNROUTABLE_PENALTY_SECONDS = 6 * 60 * 60;

function coordKey(c: { lat: number; lng: number }): string {
  return `${c.lat.toFixed(7)},${c.lng.toFixed(7)}`;
}

/**
 * Travel minutes between consecutive stops, read through the matrix's own
 * point index rather than by array position.
 *
 * This is the bug the reference implementation ships: it reads
 * `durations[i][i+1]`, assuming the matrix rows are in visit order. They are
 * not — the matrix is built before the optimizer permutes the stops, so those
 * lookups silently return the travel time between two unrelated places. The
 * total comes out plausible and wrong.
 */
function travelMinutes(orderedStops: Poi[], matrix: DurationMatrix): number {
  if (orderedStops.length < 2) return 0;

  const index = new Map<string, number>();
  matrix.points.forEach((p, i) => {
    if (!index.has(coordKey(p))) index.set(coordKey(p), i);
  });

  let seconds = 0;
  for (let i = 0; i < orderedStops.length - 1; i++) {
    const from = index.get(coordKey(orderedStops[i]!.location));
    const to = index.get(coordKey(orderedStops[i + 1]!.location));
    if (from === undefined || to === undefined) continue;
    const value = matrix.durations[from]?.[to];
    seconds += typeof value === "number" ? value : UNROUTABLE_PENALTY_SECONDS;
  }
  return seconds / 60;
}

/** Spec §7, transcribed: `TimeEstimator.estimate(...)`. */
export async function estimate(input: EstimateInput): Promise<TimeEstimate> {
  const { orderedStops, matrix, dwellTimes, timeBudgetMinutes, isochrone } = input;

  if (orderedStops.length === 0) return { totalMinutes: 0, dayCountFlag: 1 };

  const dwell = orderedStops.reduce(
    (sum, p) => sum + (dwellTimes[p.id] ?? p.avgVisitDurationMinutes),
    0,
  );
  const totalMinutes = Math.round(travelMinutes(orderedStops, matrix) + dwell);

  const dayCountFlag = await computeDayCountFlag(
    orderedStops,
    matrix,
    timeBudgetMinutes,
    dwellTimes,
    isochrone,
  );

  return { totalMinutes, dayCountFlag };
}

/**
 * How many days this route actually needs.
 *
 * Two signals, and the geographic one can only ever raise the answer:
 *
 * 1. **Sequential packing.** Walk the stops in visit order, accumulating
 *    travel plus dwell. When the next stop would overrun the day's budget, it
 *    starts a new day. This is arithmetic, and it is the floor.
 *
 * 2. **Reachability.** If the arithmetic says one day but a stop lies outside
 *    the area reachable from the first stop within the budget, the arithmetic
 *    missed something the geography knows: the matrix may describe a fast road
 *    that the isochrone shows does not actually get there in time. One stop
 *    outside is enough to make it a two-day route.
 *
 * A single stop that cannot fit in a whole day on its own is not an infinite
 * loop — it is given its own day and the caller sees a day count that says so.
 */
export async function computeDayCountFlag(
  orderedStops: Poi[],
  matrix: DurationMatrix,
  remainingBudgetMinutes: number,
  dwellTimes: Record<string, number> = {},
  isochrone?: IsochronePolygon | null,
): Promise<number> {
  if (orderedStops.length === 0) return 1;
  if (remainingBudgetMinutes <= 0) return orderedStops.length;

  let days = 1;
  let spent = 0;

  for (let i = 0; i < orderedStops.length; i++) {
    const stop = orderedStops[i]!;
    const dwell = dwellTimes[stop.id] ?? stop.avgVisitDurationMinutes;
    const travel = i === 0 ? 0 : travelMinutes([orderedStops[i - 1]!, stop], matrix);
    const needed = travel + dwell;

    if (spent > 0 && spent + needed > remainingBudgetMinutes) {
      days++;
      // The new day starts at this stop, so its inbound travel is not charged
      // against the day — the traveller sets out fresh.
      spent = dwell;
    } else {
      spent += needed;
    }
  }

  if (days === 1 && isochrone) {
    const unreachable = orderedStops.some(
      (stop) => !pointInPolygon(stop.location, isochrone.coordinates),
    );
    if (unreachable) days = 2;
  }

  return days;
}

/**
 * Ray-casting point-in-polygon against the isochrone's exterior ring.
 *
 * `IsochronePolygon.coordinates` is GeoJSON-ordered — `[lng, lat]`, outer ring
 * first — so the swap happens here and the caller keeps passing the domain's
 * `{lat, lng}` shape. Holes are ignored: an isochrone hole is a pocket the
 * network cannot reach, and treating a stop in one as reachable errs toward
 * the smaller day count, which is the direction that does not surprise a
 * traveller with an extra day they did not ask for.
 */
export function pointInPolygon(
  point: { lat: number; lng: number },
  coordinates: Array<Array<[number, number]>>,
): boolean {
  const ring = coordinates[0];
  if (!ring || ring.length < 3) return true; // No usable ring: do not accuse.

  const x = point.lng;
  const y = point.lat;
  let inside = false;

  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i]![0];
    const yi = ring[i]![1];
    const xj = ring[j]![0];
    const yj = ring[j]![1];

    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) {
      inside = !inside;
    }
  }

  return inside;
}
