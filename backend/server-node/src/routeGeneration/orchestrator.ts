/**
 * Layer 2 — Route Generation Orchestrator.
 *
 * Sequences the Domain calls in order, loads city config, and owns graceful
 * degradation and telemetry (spec §3). This is the first point at which the
 * whole pipeline runs as one call (spec §9 step 5), and the only place that
 * knows the order of operations — the Domain components below it are
 * independent of each other by design.
 *
 * Nothing here talks HTTP. Layer 1 (`routes/routes.ts`) validates, rate-limits
 * and translates errors; this layer only knows about `RouteRequest` and the
 * error vocabulary in `errors.ts`.
 */
import { createHash } from "node:crypto";

import { Config } from "../config";
import { getLogger } from "../logger";
import { getCacheAdapter, isochroneBucket, legKey } from "./adapters/cacheAdapter";
import {
  RoutingProviderAdapter,
  StraightLineRoutingProvider,
  createRoutingProviderAdapter,
} from "./adapters/routingProviderAdapter";
import { getCityConfigRepository } from "./data/cityConfigRepository";
import { getRouteRepository } from "./data/routeRepository";
import { fitToBudget, rankValue, stopsToDrop } from "./domain/budgetFitter";
import { cluster, distanceMeters } from "./domain/clusteringEngine";
import { selectPois } from "./domain/poiSelector";
import { LegGeometry, assemble, buildSegments } from "./domain/responseAssembler";
import { orderClusters, orderStopsWithinCluster } from "./domain/routeOptimizer";
import { estimate } from "./domain/timeEstimator";
import {
  CityNotAvailableError,
  CityNotFoundError,
  NoEligiblePoisError,
  TimeBudgetTooShortError,
} from "./errors";
import {
  Cluster,
  Coordinate,
  DurationMatrix,
  IsochronePolygon,
  Poi,
  RouteRequest,
  RouteResponse,
  RouteResult,
  RoutingProfile,
  SegmentMode,
} from "./types";

const logger = getLogger("routeGeneration.orchestrator");

/** Rollout statuses a route may be generated for. `planning` is visible in the
 * city list but not routable — that is the point of the phased rollout. */
const ROUTABLE_STATUSES = new Set(["pilot", "active"]);

/**
 * Minutes of travel assumed per stop during the first, pre-ordering fit.
 *
 * Measured against the seeded cities: intra-cluster walks run 3–8 minutes and
 * inter-cluster hops 3–7, so a mixed route averages a little under ten. It only
 * has to be close — the measured pass below corrects it.
 */
const TRAVEL_ALLOWANCE_PER_STOP_MINUTES = 9;

/**
 * The floor the fit will not trim below.
 *
 * One, not three. A higher floor sounds kinder and is not: a 240-minute budget
 * whose theme is one 84-minute beach forty minutes away was being handed three
 * stops and 503 minutes — a route twice as long as the traveller said they had,
 * because the fitter was forbidden from giving the honest answer. One stop is a
 * real answer to a small budget; a route that cannot be walked is not.
 *
 * Zero would be, which is why this is not zero — `NoEligiblePoisError` is the
 * right answer to "nothing matches", and an empty route is not.
 */
const MINIMUM_STOPS = 1;

/** How many times the measured trim may re-cluster before accepting what it
 * has. Each pass is pure in-memory work over ≤30 stops and reuses the matrices
 * already fetched, so this costs no provider calls — but it must terminate. */
const MAX_FIT_PASSES = 4;

/** How many replacement candidates travel with a route. Enough to survive a
 * traveller rejecting most of what they were offered, small enough that the
 * response stays a route rather than a catalogue dump. */
const MAX_ALTERNATES = 20;

/**
 * Identifies a matrix by the exact point set it covers.
 *
 * The reference implementation keys its matrix cache on `mode:pointCount`,
 * which is a live correctness bug rather than a missed optimisation: any two
 * different point sets of the same size and profile return each other's
 * matrix. In its own pipeline that fires immediately — the walking matrix is
 * cached over the *unordered* POI list, then the sequential matrix is
 * requested for the *ordered* list, same length, same profile, and the cache
 * hands back rows in the wrong order. The resulting travel times are
 * plausible and wrong.
 *
 * Fingerprinting the coordinates makes the key say what the value actually
 * is. Cache hits then only happen when they are genuinely the same question.
 */
function matrixKey(profile: RoutingProfile, points: Coordinate[]): string {
  const digest = createHash("sha1")
    .update(points.map((p) => `${p.lat.toFixed(7)},${p.lng.toFixed(7)}`).join("|"))
    .digest("hex")
    .slice(0, 16);
  return `${profile}:${digest}`;
}

/**
 * Cache-first read of the duration matrix.
 *
 * The cache-first rule is the orchestrator's, not the adapter's: on provider
 * failure a stale matrix is served instead of the request failing (spec §8,
 * "falls back to the last cached matrix on provider failure or slowness").
 */
async function loadMatrix(
  cityId: string,
  points: Coordinate[],
  profile: RoutingProfile,
  provider: RoutingProviderAdapter,
): Promise<DurationMatrix> {
  // A single point has no pairs to ask about, and providers charge for the
  // call anyway.
  if (points.length < 2) {
    return { durations: [[0]], distances: [[0]], points };
  }

  const cache = getCacheAdapter();
  const key = matrixKey(profile, points);

  const cached = await cache.getMatrix(cityId, key);
  if (cached) {
    logger.info(`matrix cache hit — ${cityId}/${key}, ${points.length} points`);
    return cached;
  }

  try {
    // ONE call for every pair. Never one call per pair — spec §4.
    const matrix = await provider.getMatrix(points, profile);
    await cache.setMatrix(cityId, key, matrix);
    return matrix;
  } catch (error) {
    // Graceful degradation, and the case that actually fires (spec §8).
    //
    // The matrix is used for two things: ordering the stops, and the travel
    // half of the duration estimate. Neither is worth failing a request over,
    // because a great-circle matrix orders a walkable cluster almost
    // identically to a road matrix — over a few hundred metres the ranking of
    // "which stop is nearest" barely changes, and it is the ranking, not the
    // absolute value, that the optimizer consumes.
    //
    // The per-leg durations, distances and polylines the traveller actually
    // reads come from `getRoute`, not from here, so they stay real even when
    // this falls back. That is why this degrades quietly instead of 503ing:
    // the free plan caps matrices at 5 points, which every city here exceeds,
    // so a hard failure would mean the module never works on a free key at
    // all.
    logger.warning(
      `${provider.name} matrix unavailable (${error instanceof Error ? error.message : error}) — ` +
        `ordering ${points.length} points by straight-line distance instead`,
    );
    const estimated = await new StraightLineRoutingProvider(provider.name).getMatrix(
      points,
      profile,
    );
    await cache.setMatrix(cityId, key, estimated);
    return estimated;
  }
}

/** Cache-first isochrone. Failure is not fatal: the day-count check degrades
 * to sequential packing, which the estimator handles explicitly. */
async function loadIsochrone(
  origin: Poi,
  timeBudgetMinutes: number,
  profile: RoutingProfile,
  provider: RoutingProviderAdapter,
): Promise<IsochronePolygon | null> {
  const cache = getCacheAdapter();
  const bucketed = isochroneBucket(timeBudgetMinutes);

  try {
    const cached = await cache.getIsochrone(origin.id, bucketed, profile);
    if (cached) return cached;

    const polygon = await provider.getIsochrone(origin.location, bucketed, profile);
    await cache.setIsochrone(origin.id, bucketed, profile, polygon);
    return polygon;
  } catch (error) {
    logger.warning(
      `isochrone unavailable (${error instanceof Error ? error.message : error}) — ` +
        "day count falls back to sequential packing",
    );
    return null;
  }
}

/**
 * Fetches the drawable geometry for every leg, cache-first.
 *
 * The matrix gives durations but not the line to draw on the map, so each leg
 * needs its own `getRoute`. That makes legs the bulk of the provider traffic —
 * a 15-stop route is two matrix calls and fourteen leg calls — and the cache
 * is what stops that being paid twice.
 *
 * Three things keep the call count down, in the order they matter:
 *
 *   1. **The cache**, keyed on the coordinate pair alone (see `legKey`). A leg
 *      is shared across every theme, budget and traveller that walks it, so
 *      the second route through the Casbah pays nothing for the hops the first
 *      one already fetched.
 *   2. **Deduplication within the request**, so a pair appearing twice in one
 *      route is fetched once. Cheap, and it also stops two identical
 *      in-flight requests both missing the cache and both calling out.
 *   3. **Concurrency**, bounded by the provider's own token bucket. Issuing
 *      them in sequence would multiply the bucket's wait by the leg count for
 *      no benefit, since the bucket already paces them.
 *
 * Every failure degrades to a straight-line estimate rather than an error. A
 * missing polyline should cost the map a curve, not cost the traveller their
 * route (spec §8).
 */
async function fetchLegs(
  orderedClusters: Cluster[],
  provider: RoutingProviderAdapter,
): Promise<{ driveLegs: LegGeometry[]; walkLegs: LegGeometry[] }> {
  const drivePairs: Array<[Coordinate, Coordinate]> = [];
  const walkPairs: Array<[Coordinate, Coordinate]> = [];
  // Whether each inter-cluster hop is short enough to walk. Decided from the
  // distance between anchors rather than from cluster membership, because those
  // answer different questions: clustering says which POIs form one walkable
  // loop, this says whether you can walk from one loop to the next. Conflating
  // them is what told a traveller to drive 600 m across central Algiers.
  const hopModes: SegmentMode[] = [];

  for (let ci = 0; ci < orderedClusters.length; ci++) {
    const current = orderedClusters[ci]!;
    if (ci > 0) {
      const previous = orderedClusters[ci - 1]!.anchor;
      drivePairs.push([previous, current.anchor]);
      hopModes.push(
        distanceMeters(previous, current.anchor) <= Config.ROUTE_WALKABLE_HOP_METERS
          ? "walk"
          : "drive",
      );
    }
    for (let pi = 0; pi < current.pois.length - 1; pi++) {
      walkPairs.push([current.pois[pi]!.location, current.pois[pi + 1]!.location]);
    }
  }

  const cache = getCacheAdapter();
  const estimator = new StraightLineRoutingProvider(provider.name);
  // One promise per distinct leg, shared by every position that wants it.
  const inFlight = new Map<string, Promise<RouteResult>>();
  let hits = 0;
  let fetched = 0;

  const leg = (
    [from, to]: [Coordinate, Coordinate],
    profile: RoutingProfile,
  ): Promise<RouteResult> => {
    const key = legKey(from, to, profile);
    const existing = inFlight.get(key);
    if (existing) return existing;

    const promise = (async (): Promise<RouteResult> => {
      const cached = await cache.getLeg(from, to, profile);
      if (cached) {
        hits++;
        return cached;
      }
      try {
        const result = await provider.getRoute([from, to], profile);
        await cache.setLeg(from, to, profile, result);
        fetched++;
        return result;
      } catch {
        // Estimated rather than zeroed. A zero-minute, zero-metre leg is not a
        // degraded answer, it is a false one: it tells the traveller two
        // places are the same place, and it silently shrinks the route's
        // total. The straight-line estimate is wrong by a knowable margin
        // instead.
        //
        // Deliberately NOT cached: this is a failure, not an answer, and
        // storing it for a week would keep serving the estimate long after
        // whatever rate limit caused it had cleared.
        return estimator.getRoute([from, to], profile);
      }
    })();

    inFlight.set(key, promise);
    return promise;
  };

  const [driveLegs, walkLegs] = await Promise.all([
    // Routed with the profile that matches the tag: a hop tagged `walk` gets a
    // walking route, so its polyline follows the alleys a car cannot take and
    // its duration is a walking duration. Tagging it a walk while routing it by
    // car would be the same lie in a different place.
    Promise.all(
      drivePairs.map(async (p, i) => ({
        ...(await leg(p, hopModes[i] === "walk" ? "walking" : "driving")),
        mode: hopModes[i]!,
      })),
    ),
    Promise.all(walkPairs.map((p) => leg(p, "walking"))),
  ]);

  logger.info(
    `legs: ${hits} cached, ${fetched} fetched, ` +
      `${drivePairs.length + walkPairs.length - hits - fetched} estimated`,
  );

  return { driveLegs, walkLegs };
}

/**
 * The whole pipeline, in the order of spec §4's Figure 2.
 *
 *   1. Route request received
 *   2. Load city config
 *   3. POI Selector
 *   4. Clustering Engine
 *   5. Route Optimizer          → Cache Adapter → Routing Provider (getMatrix)
 *   6. Time & Reachability      → Routing Provider (getIsochrone)
 *   7. Response Assembler
 *   8. Persist route
 *   9. Return response
 */
export async function generateRoute(request: RouteRequest): Promise<RouteResponse> {
  return generateExcluding(request, new Set());
}

async function generateExcluding(
  request: RouteRequest,
  excludePoiIds: Set<string>,
): Promise<RouteResponse> {
  const startedAt = Date.now();

  // 2. Load city config — cluster radius, active provider, rollout status.
  const city = await getCityConfigRepository().findById(request.cityId);
  if (!city) throw new CityNotFoundError(request.cityId);
  if (!ROUTABLE_STATUSES.has(city.rolloutStatus)) {
    throw new CityNotAvailableError(request.cityId, city.rolloutStatus);
  }

  const provider = createRoutingProviderAdapter(city.activeRoutingProvider);

  // 3. POI Selector — published POIs matching theme + hours.
  // No opening-hours filter, deliberately.
  //
  // It used to pass `new Date()`, which filtered against the moment the button
  // was pressed rather than when the traveller will actually be there — and a
  // route is planned ahead, not walked on the spot. The effect was severe and
  // invisible: generating an Algiers route at 19:40 dropped nine of fifteen
  // POIs as "closed", so the same request produced a fifteen-stop route in the
  // morning and a six-stop one that evening, with different clusters, a
  // different drive/walk split and a different day count.
  //
  // The request carries no visit time, so there is nothing honest to filter
  // against. Every published POI stays eligible and each stop carries its
  // `openingHoursRaw` to the client, which can say "closes at 17:00" — true at
  // any hour, unlike silently removing it. Restore the filter when the request
  // gains a start time; `selectPois` still takes `now` for exactly that.
  const selected = await selectPois({
    cityId: request.cityId,
    theme: request.theme,
    categoryKeys: request.categoryKeys,
    locale: request.locale,
  });
  const pois = selected.filter((p) => !excludePoiIds.has(p.id));
  if (pois.length === 0) throw new NoEligiblePoisError(request.theme);

  // Ranking-only, never eligibility — see budgetFitter.ts's module docstring.
  // Comes from the prompt interpreter (domain/promptInterpreter.ts), not the
  // request builder's category chips: `request.categoryKeys` already
  // narrowed `pois` above via selectPois, so a key present in both places
  // has already done its filtering work and only adds a ranking nudge here.
  const preferredCategoryKeys = new Set(request.preferredCategoryKeys ?? []);

  // Even the shortest single visit has to fit. Raised here rather than letting
  // the estimator return a day count for a route with nothing in it: the
  // honest answer to "I have 20 minutes" is that no stop in this city works,
  // not a one-stop route the traveller cannot complete.
  const shortestDwell = Math.min(...pois.map((p) => p.avgVisitDurationMinutes));
  if (shortestDwell > request.timeBudgetMinutes) {
    throw new TimeBudgetTooShortError(request.timeBudgetMinutes);
  }

  // 3b. Fit the budget.
  //
  // NOT IN SPEC — see budgetFitter.ts. Without this the module selects every
  // eligible POI and reports the overrun through the day-count flag, which
  // produced a 21-stop, 26-hour Algiers route against an eight-hour request.
  //
  // Two passes, because the exact cost of a stop is not knowable before there
  // is an ordering and the ordering depends on which stops there are. This one
  // works from a flat travel allowance; the loop below measures the real route
  // and trims what is still over.
  const selectedForBudget = fitToBudget({
    pois,
    timeBudgetMinutes: request.timeBudgetMinutes,
    travelAllowancePerStopMinutes: TRAVEL_ALLOWANCE_PER_STOP_MINUTES,
    minimumStops: MINIMUM_STOPS,
    preferredCategoryKeys,
  });

  if (selectedForBudget.length < pois.length) {
    logger.info(
      `budget fit: ${pois.length} eligible → ${selectedForBudget.length} stops ` +
        `for ${request.timeBudgetMinutes} minutes`,
    );
  }

  // 4. Clustering Engine — group into walkable clusters by the city's radius.
  const clusters: Cluster[] = cluster(selectedForBudget, city.clusterRadiusMeters);

  // 5. Route Optimizer — clusters by driving time, stops within by walking.
  //
  // Two matrices, one call each, each covering every pair it needs (spec §4).
  // The ordering functions look their rows up by coordinate rather than by
  // array position, so permuting the clusters below does not invalidate the
  // walking matrix built before it.
  const anchors = clusters.map((c) => c.anchor);
  const allStops = clusters.flatMap((c) => c.pois.map((p) => p.location));

  const [drivingMatrix, walkingMatrix] = await Promise.all([
    loadMatrix(request.cityId, anchors, "driving", provider),
    loadMatrix(request.cityId, allStops, "walking", provider),
  ]);

  // 5b. Order, measure, trim, repeat.
  //
  // The measured half of the budget fit. The pre-fit above worked from a flat
  // travel allowance because there was no ordering to measure; now there is
  // one, so the overshoot is exact and the worst stops can be dropped by how
  // much time they actually cost.
  //
  // Re-clustering each pass matters and is not wasted work: removing a stop can
  // empty a cluster, which removes an entire drive leg, which is usually a
  // bigger saving than the stop's own dwell. Every pass is in-memory and reuses
  // the matrices already fetched — the optimizer looks its rows up by
  // coordinate, so a subset works against the same matrix without a new
  // provider call.
  let working = selectedForBudget;
  let orderedClusters = orderClusters(cluster(working, city.clusterRadiusMeters), drivingMatrix)
    .map((c) => ({ ...c, pois: orderStopsWithinCluster(c, walkingMatrix) }));
  let orderedStops = orderedClusters.flatMap((c) => c.pois);
  let measured = await estimate({
    orderedStops,
    matrix: walkingMatrix,
    dwellTimes: Object.fromEntries(orderedStops.map((p) => [p.id, p.avgVisitDurationMinutes])),
    timeBudgetMinutes: request.timeBudgetMinutes,
  });

  for (let pass = 0; pass < MAX_FIT_PASSES; pass++) {
    const overshoot = measured.totalMinutes - request.timeBudgetMinutes;
    if (overshoot <= 0 || orderedStops.length <= MINIMUM_STOPS) break;

    const drop = stopsToDrop(
      orderedStops,
      overshoot,
      MINIMUM_STOPS,
      TRAVEL_ALLOWANCE_PER_STOP_MINUTES,
      preferredCategoryKeys,
    );
    if (drop.size === 0) break;

    working = working.filter((p) => !drop.has(p.id));
    orderedClusters = orderClusters(cluster(working, city.clusterRadiusMeters), drivingMatrix)
      .map((c) => ({ ...c, pois: orderStopsWithinCluster(c, walkingMatrix) }));
    orderedStops = orderedClusters.flatMap((c) => c.pois);
    measured = await estimate({
      orderedStops,
      matrix: walkingMatrix,
      dwellTimes: Object.fromEntries(orderedStops.map((p) => [p.id, p.avgVisitDurationMinutes])),
      timeBudgetMinutes: request.timeBudgetMinutes,
    });

    logger.info(
      `budget trim pass ${pass + 1}: dropped ${drop.size}, ` +
        `${orderedStops.length} stops, ${measured.totalMinutes}/${request.timeBudgetMinutes} min`,
    );
  }

  // 5c. Put back what the trim overshot.
  //
  // The trim only ever removes, and it removes in whole stops — so a route
  // eighty minutes over drops a ninety-minute stop and lands well under. That
  // showed up as the one thing a budget fit must never do: a larger budget
  // returning a shorter route. Adding the best of the dropped stops back, one
  // at a time and only while the measured route still fits, closes the gap and
  // makes the result monotone in the budget.
  //
  // Best-value-first and re-measured each time, because a stop that fits alone
  // may not fit after the one before it was added.
  const droppedIds = new Set(selectedForBudget.map((p) => p.id));
  for (const poi of working) droppedIds.delete(poi.id);

  if (droppedIds.size > 0) {
    const candidates = selectedForBudget
      .filter((p) => droppedIds.has(p.id))
      .sort((a, b) => rankValue(b, preferredCategoryKeys) - rankValue(a, preferredCategoryKeys));

    for (const candidate of candidates) {
      const trial = [...working, candidate];
      const trialClusters = orderClusters(
        cluster(trial, city.clusterRadiusMeters),
        drivingMatrix,
      ).map((c) => ({ ...c, pois: orderStopsWithinCluster(c, walkingMatrix) }));
      const trialStops = trialClusters.flatMap((c) => c.pois);
      const trialEstimate = await estimate({
        orderedStops: trialStops,
        matrix: walkingMatrix,
        dwellTimes: Object.fromEntries(
          trialStops.map((p) => [p.id, p.avgVisitDurationMinutes]),
        ),
        timeBudgetMinutes: request.timeBudgetMinutes,
      });
      if (trialEstimate.totalMinutes > request.timeBudgetMinutes) continue;

      working = trial;
      orderedClusters = trialClusters;
      orderedStops = trialStops;
      measured = trialEstimate;
    }
  }

  logger.info(
    `budget fit: ${orderedStops.length} stops, ` +
      `${measured.totalMinutes}/${request.timeBudgetMinutes} min`,
  );

  // 6. Time & Reachability Estimator — the isochrone check that sets the
  //    day-count flag, now against the route that will actually be returned.
  const isochrone = orderedStops[0]
    ? await loadIsochrone(orderedStops[0], request.timeBudgetMinutes, "driving", provider)
    : null;

  const timeEstimate = await estimate({
    orderedStops,
    matrix: walkingMatrix,
    dwellTimes: Object.fromEntries(orderedStops.map((p) => [p.id, p.avgVisitDurationMinutes])),
    timeBudgetMinutes: request.timeBudgetMinutes,
    isochrone,
  });

  // 7. Response Assembler — segments, mode tags, checkpoint radii.
  const { driveLegs, walkLegs } = await fetchLegs(orderedClusters, provider);
  const segments = buildSegments(orderedClusters, driveLegs, walkLegs);

  // Everything eligible that the budget could not pay for, best first. The
  // review step spends these when the traveller rejects a stop — without them
  // a rejection can only make the route shorter than the budget they asked for.
  const chosenIds = new Set(orderedStops.map((p) => p.id));
  const alternates = pois
    .filter((p) => !chosenIds.has(p.id))
    .sort((a, b) => rankValue(b, preferredCategoryKeys) - rankValue(a, preferredCategoryKeys))
    .slice(0, MAX_ALTERNATES);

  const route = assemble({
    request,
    orderedClusters,
    segments,
    estimate: timeEstimate,
    alternates,
  });

  // 8. Persist — immutable route definition plus its stops.
  const routeId = await getRouteRepository().persist({
    route,
    userId: request.userId ?? null,
    sessionId: request.sessionId ?? null,
  });

  logger.info(
    `route ${routeId} generated for city ${request.cityId} in ${Date.now() - startedAt}ms ` +
      `(${route.stops.length} stops, ${route.segments.length} segments, ` +
      `day flag ${route.dayCountFlag})`,
  );

  // 9. Return.
  return { ...route, id: routeId };
}

/**
 * NOT IN SPEC.
 *
 * The app's flow lets a traveller review the generated route and drop stops
 * they do not want, then see the route re-optimized. The spec has no such
 * step: routes are immutable once generated (§7) and there is no partial-route
 * concept anywhere in it.
 *
 * Modelled as "generate a new route excluding these POIs" rather than as a
 * mutation, so the immutability rule survives — the original route row is
 * untouched and a second one is written. `routeId` is therefore only read to
 * confirm the caller owns the route they are refining; the new route does not
 * reference it.
 */
export async function refineRoute(
  routeId: string,
  dropPoiIds: string[],
  request: RouteRequest,
): Promise<RouteResponse> {
  const original = await getRouteRepository().findById(routeId, request.userId ?? null);
  // A refine against a route the caller cannot see is answered as a fresh
  // generation rather than an error: the request carries everything needed,
  // and the only thing lost is the exclusion of stops we cannot confirm.
  if (!original) {
    logger.warning(`refine: route ${routeId} not found or not owned — generating fresh`);
  }

  return generateExcluding(request, new Set(dropPoiIds));
}
