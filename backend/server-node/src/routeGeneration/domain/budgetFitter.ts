/**
 * Layer 3 — Budget Fitter. Pure function, no dependencies.
 *
 * NOT IN SPEC. §5 specifies the day-count flag as the answer to "this does not
 * fit": select everything eligible, then report how many days it would take.
 * That is defensible for a curated catalogue of a dozen stops and stops being
 * defensible the moment the catalogue is real — an Algiers route came back as
 * 21 stops and 1,595 minutes flagged as four days against an eight-hour
 * budget. A traveller who says they have a day should be given a day, not a
 * four-day itinerary with a warning on it.
 *
 * So the budget becomes a constraint rather than a report. This drops stops
 * until the route fits, and the day-count flag goes back to meaning what §5
 * says it means: 1 when it fits, 2+ only when even a minimal route cannot.
 *
 * ## What gets dropped
 *
 * The least rewarding minute, not the least interesting stop. A POI is kept or
 * dropped on `interestScore / dwellMinutes` — value per minute spent — because
 * the thing being rationed is time. A merely-good museum that takes 63 minutes
 * loses to two good monuments that take 25 each, and it should: the traveller
 * ends the day having seen more of what they came for.
 *
 * Stops with no score are treated as mid-ranked rather than worthless. A null
 * score means "never scored" — true of every hand-authored row — and dropping
 * those first would quietly prefer machine-ingested POIs over curated ones.
 */
import { Poi } from "../types";

export interface FitInput {
  /** Every eligible POI, best-first is not required. */
  pois: Poi[];
  /** Total minutes available across the whole trip. */
  timeBudgetMinutes: number;
  /**
   * Minutes of travel to assume per stop, on top of dwell.
   *
   * The real figure is not knowable here — it depends on an ordering that does
   * not exist until after selection, which depends on the selection. Rather
   * than iterate to a fixed point, this reserves a flat allowance per stop and
   * the orchestrator re-checks against the true estimate afterwards.
   */
  travelAllowancePerStopMinutes: number;
  /** Never return fewer than this, even if the budget cannot pay for them —
   * a route of nothing is not a useful answer to "I have twenty minutes". */
  minimumStops: number;
}

/** Value per minute. Null scores sit mid-range so an unscored curated POI is
 * not silently ranked below every ingested one. */
const UNSCORED_VALUE = 40;

export function valuePerMinute(poi: Poi): number {
  const value = poi.interestScore ?? UNSCORED_VALUE;
  const cost = Math.max(1, poi.avgVisitDurationMinutes);
  return value / cost;
}

/**
 * The largest subset of `pois` whose dwell plus a travel allowance fits the
 * budget, taking the most rewarding minutes first.
 *
 * Order is not decided here — that is the Route Optimizer's job, and it runs
 * after this on a smaller set. This only answers *which* stops.
 */
export function fitToBudget(input: FitInput): Poi[] {
  const { pois, timeBudgetMinutes, travelAllowancePerStopMinutes, minimumStops } = input;
  if (pois.length === 0) return [];

  const ranked = [...pois].sort((a, b) => {
    const byValue = valuePerMinute(b) - valuePerMinute(a);
    if (byValue !== 0) return byValue;
    // Stable and deterministic: two POIs of identical value density must not
    // swap between two generations of the same request.
    return a.id.localeCompare(b.id);
  });

  const kept: Poi[] = [];
  let spent = 0;

  for (const poi of ranked) {
    const cost = poi.avgVisitDurationMinutes + travelAllowancePerStopMinutes;
    if (kept.length >= minimumStops && spent + cost > timeBudgetMinutes) continue;
    kept.push(poi);
    spent += cost;
  }

  return kept;
}

/**
 * Drops the least rewarding stops from an already-ordered route until its
 * measured duration fits.
 *
 * The second half of the fit, and the one that uses real numbers. `fitToBudget`
 * works from an allowance because it runs before there is an ordering to
 * measure; once the route exists, its estimate is exact, and a route that
 * overshoots by forty minutes should lose forty minutes of its worst stops
 * rather than be re-guessed from scratch.
 *
 * Returns the ids to remove, so the caller re-clusters and re-orders — the
 * shape of the route genuinely changes when a stop leaves a cluster.
 */
export function stopsToDrop(
  orderedStops: Poi[],
  overshootMinutes: number,
  minimumStops: number,
  travelAllowancePerStopMinutes: number,
): Set<string> {
  const drop = new Set<string>();
  if (overshootMinutes <= 0 || orderedStops.length <= minimumStops) return drop;

  const worstFirst = [...orderedStops].sort((a, b) => {
    const byValue = valuePerMinute(a) - valuePerMinute(b);
    if (byValue !== 0) return byValue;
    return a.id.localeCompare(b.id);
  });

  let shed = 0;
  for (const poi of worstFirst) {
    if (orderedStops.length - drop.size <= minimumStops) break;
    if (shed >= overshootMinutes) break;
    drop.add(poi.id);
    // Dwell *plus* the travel a stop carries. Counting dwell alone looked
    // conservative and was the opposite: on a travel-heavy route — parks and
    // beaches spread across a city — the overshoot is mostly driving, so
    // shedding it in 60-minute dwell units dropped far more stops than the
    // overshoot needed. That produced the indefensible result of a larger
    // budget returning a shorter route: Oran at 480 minutes came back with one
    // stop where 240 minutes had given three.
    shed += poi.avgVisitDurationMinutes + travelAllowancePerStopMinutes;
  }

  return drop;
}
