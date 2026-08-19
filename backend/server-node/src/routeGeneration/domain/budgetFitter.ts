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
 *
 * ## Preferred categories
 *
 * NOT IN SPEC. `RouteRequest.preferredCategoryKeys` — the categories an LLM
 * read out of the traveller's free-text prompt (`domain/promptInterpreter.ts`)
 * — are a ranking preference, not an eligibility filter: "show me beaches"
 * should mean beaches sort to the top of a tight budget and survive a trim,
 * not that every non-beach POI is invisible to selection. `rankValue` is
 * `valuePerMinute` with a flat multiplier for a preferred category, and it is
 * what actually orders stops in and drops stops out — `valuePerMinute` alone
 * stays the number recorded/reasoned about elsewhere (it is also exported
 * for that).
 *
 * The multiplier is not enough on its own, because `valuePerMinute` divides by
 * dwell and preferred categories are often the long ones. So each preferred
 * category also gets one guaranteed representative: seeded ahead of the value
 * order in `fitToBudget` (still subject to the budget) and protected from
 * `stopsToDrop` while it is the last of its category standing. Everything past
 * that first stop per category is ordinary ranking again — the guarantee is
 * "you asked for beaches, so there is a beach", not "beaches only".
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
  /** Category keys to rank up — see the module docstring. Not a filter: a
   * POI outside this set is never excluded on that basis alone. */
  preferredCategoryKeys?: ReadonlySet<string>;
}

/** Value per minute. Null scores sit mid-range so an unscored curated POI is
 * not silently ranked below every ingested one. */
const UNSCORED_VALUE = 40;

/**
 * The best POI in each preferred category, best-first across categories.
 *
 * The boost alone cannot carry a category whose POIs are long: `valuePerMinute`
 * divides by dwell, so Oran's two beaches (100 and 120 minutes) score 0.33–0.40
 * against a 45-minute park's 0.89, and 1.5x does not close a 2.7x gap. Raising
 * the multiplier until it did would be tuning one city's numbers into a
 * constant — and would then over-promote short preferred POIs everywhere else.
 *
 * So the multiplier keeps doing what it is good at (ordering *within* a
 * plausible set) and this handles the part it cannot: making sure the thing
 * the traveller actually named appears at all. One per category, because
 * "beaches and gardens" names two things and getting only gardens back is the
 * same failure as getting neither.
 */
function bestPerPreferredCategory(
  pois: Poi[],
  preferredCategoryKeys: ReadonlySet<string> | undefined,
): Poi[] {
  if (!preferredCategoryKeys || preferredCategoryKeys.size === 0) return [];

  const best = new Map<string, Poi>();
  for (const poi of pois) {
    if (!preferredCategoryKeys.has(poi.categoryKey)) continue;
    const incumbent = best.get(poi.categoryKey);
    if (
      !incumbent ||
      valuePerMinute(poi) > valuePerMinute(incumbent) ||
      (valuePerMinute(poi) === valuePerMinute(incumbent) && poi.id < incumbent.id)
    ) {
      best.set(poi.categoryKey, poi);
    }
  }

  return [...best.values()].sort((a, b) => {
    const byValue = valuePerMinute(b) - valuePerMinute(a);
    return byValue !== 0 ? byValue : a.id.localeCompare(b.id);
  });
}

export function valuePerMinute(poi: Poi): number {
  const value = poi.interestScore ?? UNSCORED_VALUE;
  const cost = Math.max(1, poi.avgVisitDurationMinutes);
  return value / cost;
}

/**
 * How much a preferred-category match is worth over an equally-scored POI
 * outside it. Large enough that "beaches" reliably outranks a same-scored
 * museum on a tight budget, not so large that a genuinely poor beach (a low
 * `interestScore`) beats a genuinely excellent stop in another category —
 * a flat multiplier on `valuePerMinute` preserves that ordering rather than
 * a flat bonus, which would let a preferred category's worst POI outrank a
 * non-preferred category's best.
 */
const PREFERRED_CATEGORY_BOOST = 1.5;

/** `valuePerMinute`, boosted for a category the traveller's prompt called
 * out. This — not `valuePerMinute` — is what selection, trimming and
 * alternate ordering actually sort by. */
export function rankValue(poi: Poi, preferredCategoryKeys?: ReadonlySet<string>): number {
  const base = valuePerMinute(poi);
  return preferredCategoryKeys?.has(poi.categoryKey) ? base * PREFERRED_CATEGORY_BOOST : base;
}

/**
 * The largest subset of `pois` whose dwell plus a travel allowance fits the
 * budget, taking the most rewarding minutes first.
 *
 * Order is not decided here — that is the Route Optimizer's job, and it runs
 * after this on a smaller set. This only answers *which* stops.
 */
export function fitToBudget(input: FitInput): Poi[] {
  const { pois, timeBudgetMinutes, travelAllowancePerStopMinutes, minimumStops, preferredCategoryKeys } =
    input;
  if (pois.length === 0) return [];

  const ranked = [...pois].sort((a, b) => {
    const byValue = rankValue(b, preferredCategoryKeys) - rankValue(a, preferredCategoryKeys);
    if (byValue !== 0) return byValue;
    // Stable and deterministic: two POIs of identical value density must not
    // swap between two generations of the same request.
    return a.id.localeCompare(b.id);
  });

  // The prompt's own categories go first, one each — see
  // `bestPerPreferredCategory`. They are seeded rather than appended so the
  // budget check below still applies to them: a guarantee that a beach is
  // *considered* first, not that an eight-hour beach fits a one-hour trip.
  // Everything else keeps its value order behind them.
  const guaranteed = bestPerPreferredCategory(pois, preferredCategoryKeys);
  const guaranteedIds = new Set(guaranteed.map((p) => p.id));
  const order = [...guaranteed, ...ranked.filter((p) => !guaranteedIds.has(p.id))];

  const kept: Poi[] = [];
  let spent = 0;

  for (const poi of order) {
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
  preferredCategoryKeys?: ReadonlySet<string>,
): Set<string> {
  const drop = new Set<string>();
  if (overshootMinutes <= 0 || orderedStops.length <= minimumStops) return drop;

  const worstFirst = [...orderedStops].sort((a, b) => {
    const byValue = rankValue(a, preferredCategoryKeys) - rankValue(b, preferredCategoryKeys);
    if (byValue !== 0) return byValue;
    return a.id.localeCompare(b.id);
  });

  // How many stops each preferred category still has. The trim measures real
  // travel, and a preferred POI is often the far-flung one (a beach outside
  // town is exactly the stop a travel-heavy overshoot wants to shed), so
  // without this the selection guarantee above survives fitToBudget and then
  // quietly dies here — the traveller asked for a beach, saw one selected, and
  // got a route without one.
  const remainingPerPreferred = new Map<string, number>();
  for (const poi of orderedStops) {
    if (preferredCategoryKeys?.has(poi.categoryKey)) {
      remainingPerPreferred.set(poi.categoryKey, (remainingPerPreferred.get(poi.categoryKey) ?? 0) + 1);
    }
  }

  let shed = 0;
  for (const poi of worstFirst) {
    if (orderedStops.length - drop.size <= minimumStops) break;
    if (shed >= overshootMinutes) break;
    const remaining = remainingPerPreferred.get(poi.categoryKey);
    // Its category's last representative — skip it and keep shedding
    // elsewhere. Skip, not break: the stops after it are still droppable.
    if (remaining !== undefined && remaining <= 1) continue;
    if (remaining !== undefined) remainingPerPreferred.set(poi.categoryKey, remaining - 1);
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
