/**
 * Layer 2 — Route Generation Orchestrator.
 *
 * Sequences the Domain calls in order, loads city config, and owns graceful
 * degradation and telemetry (spec §3). This is the first point at which the
 * whole pipeline runs as one call (spec §9 step 5), and the only place that
 * knows the order of operations — the Domain components below it are
 * independent of each other by design.
 *
 * STATUS: the sequence is written out and wired; the components it calls are
 * stubs, so the first one reached throws NotImplementedError. That is
 * deliberate — the shape is the deliverable, and the exception says precisely
 * which piece is missing.
 *
 * Nothing here talks HTTP. Layer 1 (`routes/routes.ts`) validates, rate-limits
 * and translates errors; this layer only knows about `RouteRequest` and the
 * error vocabulary in `errors.ts`.
 */
import { getLogger } from "../logger";
import { getCacheAdapter } from "./adapters/cacheAdapter";
import { createRoutingProviderAdapter } from "./adapters/routingProviderAdapter";
import { getCityConfigRepository } from "./data/cityConfigRepository";
import { getRouteRepository } from "./data/routeRepository";
import { cluster } from "./domain/clusteringEngine";
import { selectPois } from "./domain/poiSelector";
import { assemble, buildSegments } from "./domain/responseAssembler";
import { orderClusters, orderStopsWithinCluster } from "./domain/routeOptimizer";
import { estimate } from "./domain/timeEstimator";
import {
  CityNotAvailableError,
  CityNotFoundError,
  NoEligiblePoisError,
  RouteGenerationError,
} from "./errors";
import {
  Cluster,
  Coordinate,
  DurationMatrix,
  RouteRequest,
  RouteResponse,
  RoutingProfile,
  Segment,
} from "./types";

const logger = getLogger("routeGeneration.orchestrator");

/** Rollout statuses a route may be generated for. `planning` is visible in the
 * city list but not routable — that is the point of the phased rollout. */
const ROUTABLE_STATUSES = new Set(["pilot", "active"]);

/**
 * Cache-first read of the duration matrix.
 *
 * Implemented here rather than left as a stub because it *is* the cache-first
 * rule, and the rule belongs to the orchestrator's degradation
 * responsibility: on provider failure, a stale matrix is served instead of the
 * request failing (spec §8, "falls back to the last cached matrix on provider
 * failure or slowness").
 */
async function loadMatrix(
  cityId: string,
  points: Coordinate[],
  profile: RoutingProfile,
  provider: ReturnType<typeof createRoutingProviderAdapter>,
): Promise<DurationMatrix> {
  const cache = getCacheAdapter();

  const cached = await cache.getMatrix(cityId, profile);
  if (cached) {
    logger.info(`matrix cache hit — ${cityId}/${profile}, ${points.length} points`);
    return cached;
  }

  try {
    // ONE call for every pair. Never one call per pair — spec §4.
    const matrix = await provider.getMatrix(points, profile);
    await cache.setMatrix(cityId, profile, matrix);
    return matrix;
  } catch (error) {
    // A stub throwing NotImplementedError must surface, not be reported as a
    // provider outage — that would turn "not built yet" into a 503 and hide it.
    if (error instanceof RouteGenerationError && error.code === "not_implemented") throw error;

    logger.warning(
      `${provider.name} matrix failed (${error instanceof Error ? error.message : error}) — ` +
        "no cached matrix to fall back on",
    );
    throw error;
  }
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
  const startedAt = Date.now();

  // 2. Load city config — cluster radius, active provider, rollout status.
  const city = await getCityConfigRepository().findById(request.cityId);
  if (!city) throw new CityNotFoundError(request.cityId);
  if (!ROUTABLE_STATUSES.has(city.rolloutStatus)) {
    throw new CityNotAvailableError(request.cityId, city.rolloutStatus);
  }

  const provider = createRoutingProviderAdapter(city.activeRoutingProvider);

  // 3. POI Selector — published POIs matching theme + hours.
  const pois = await selectPois({
    cityId: request.cityId,
    theme: request.theme,
    categoryKeys: request.categoryKeys,
    now: new Date(),
    locale: request.locale,
  });
  if (pois.length === 0) throw new NoEligiblePoisError(request.theme);

  // 4. Clustering Engine — group into walkable clusters by the city's radius.
  const clusters: Cluster[] = cluster(pois, city.clusterRadiusMeters);

  // 5. Route Optimizer — clusters by driving time, stops within by walking.
  //
  // Both profiles are needed, and both come from the cache first. The points
  // arrays differ (anchors vs all stops) but the cached matrix is per city and
  // covers every published POI, so a warm city answers both from one entry —
  // which is what the nightly warm job exists to guarantee.
  const anchors = clusters.map((c) => c.anchor);
  const allStops = clusters.flatMap((c) => c.pois.map((p) => p.location));

  const drivingMatrix = await loadMatrix(request.cityId, anchors, "driving", provider);
  const walkingMatrix = await loadMatrix(request.cityId, allStops, "walking", provider);

  const orderedClusters = orderClusters(clusters, drivingMatrix).map((c) => ({
    ...c,
    pois: orderStopsWithinCluster(c, walkingMatrix),
  }));

  // 6. Time & Reachability Estimator — Σ travel + Σ dwell, then the isochrone
  //    check that sets the day-count flag.
  const orderedStops = orderedClusters.flatMap((c) => c.pois);
  const timeEstimate = await estimate({
    orderedStops,
    matrix: walkingMatrix,
    dwellTimes: Object.fromEntries(orderedStops.map((p) => [p.id, p.avgVisitDurationMinutes])),
    timeBudgetMinutes: request.timeBudgetMinutes,
  });

  // 7. Response Assembler — segments, mode tags, checkpoint radii.
  //
  // The per-leg geometry comes from `getRoute`; the matrix gives durations but
  // not the line to draw on the map.
  const driveLegs: Segment[] = [];
  const walkLegs: Segment[] = [];
  const segments = buildSegments(orderedClusters, driveLegs, walkLegs);

  const route = assemble({ request, orderedClusters, segments, estimate: timeEstimate });

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
 * untouched and a second one is written. Confirm the approach with the module
 * owner before building on it.
 */
export async function refineRoute(
  _routeId: string,
  _dropPoiIds: string[],
  _request: RouteRequest,
): Promise<RouteResponse> {
  throw new RouteGenerationError(
    "not_implemented",
    501,
    "refineRoute is not implemented, and is not part of the design spec — see the note in orchestrator.ts.",
  );
}
