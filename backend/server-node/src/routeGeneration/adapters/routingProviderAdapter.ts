/**
 * Layer 4 — Routing Provider Adapter.
 *
 * The single seam to the routing engine, and the only file in this module
 * allowed to know a provider exists. Domain code never imports a provider SDK;
 * that is what makes swapping providers, or self-hosting later, a one-file
 * change (spec §2).
 *
 * STATUS: interface only. Every method throws NotImplementedError.
 * Build order puts this first because it carries the highest external
 * uncertainty (spec §9, step 2).
 *
 * Provider notes from spec §6 that constrain the implementation:
 *   • GraphHopper (hosted) is primary — free plan, no credit card, but its
 *     free tier is non-commercial-use-only.
 *   • OpenRouteService (hosted) is the alternate — 2,500 requests/day, no card.
 *   • Neither has room for a per-pair matrix call. `getMatrix` MUST cover
 *     every cluster and stop pair in ONE request (spec §4).
 *   • The adapter enforces its own timeout and falls back to the last cached
 *     matrix on provider failure or slowness (spec §8) — so a failure here is
 *     only fatal when the Cache Adapter also has nothing.
 */
import { getLogger } from "../../logger";
import { NotImplementedError } from "../errors";
import {
  Coordinate,
  DurationMatrix,
  IsochronePolygon,
  RouteResult,
  RoutingProfile,
  RoutingProviderName,
} from "../types";

const logger = getLogger("routeGeneration.routingProvider");

/** Spec §7, transcribed. */
export interface RoutingProviderAdapter {
  readonly name: RoutingProviderName;

  getRoute(stops: Coordinate[], mode: RoutingProfile): Promise<RouteResult>;

  /**
   * All-pairs durations for `points`. ONE request — see the module docstring.
   */
  getMatrix(points: Coordinate[], mode: RoutingProfile): Promise<DurationMatrix>;

  getIsochrone(
    origin: Coordinate,
    timeBudgetMinutes: number,
    mode: RoutingProfile,
  ): Promise<IsochronePolygon>;
}

/** How long the adapter waits before giving up and letting the caller fall
 * back to cache. Deliberately well inside the 1.5 s cold-cache ceiling in
 * spec §4, since a matrix and an isochrone call can both be needed. */
export const PROVIDER_TIMEOUT_MS = 4_000;

abstract class BaseRoutingProviderAdapter implements RoutingProviderAdapter {
  abstract readonly name: RoutingProviderName;

  getRoute(_stops: Coordinate[], _mode: RoutingProfile): Promise<RouteResult> {
    throw new NotImplementedError(`${this.name} getRoute`);
  }

  getMatrix(_points: Coordinate[], _mode: RoutingProfile): Promise<DurationMatrix> {
    throw new NotImplementedError(`${this.name} getMatrix`);
  }

  getIsochrone(
    _origin: Coordinate,
    _timeBudgetMinutes: number,
    _mode: RoutingProfile,
  ): Promise<IsochronePolygon> {
    throw new NotImplementedError(`${this.name} getIsochrone`);
  }
}

/**
 * Primary provider.
 *
 * Endpoints to implement against:
 *   POST https://graphhopper.com/api/1/matrix?key=…   { points, out_arrays }
 *   GET  https://graphhopper.com/api/1/route?key=…
 *   GET  https://graphhopper.com/api/1/isochrone?key=…
 *
 * GraphHopper takes coordinates as [lng, lat]; `Coordinate` here is {lat,lng},
 * so the swap belongs in this class and nowhere above it.
 */
export class GraphHopperAdapter extends BaseRoutingProviderAdapter {
  readonly name = "graphhopper" as const;
}

/**
 * Backup provider. Same three capabilities, different request shapes:
 *   POST https://api.openrouteservice.org/v2/matrix/{profile}
 *   POST https://api.openrouteservice.org/v2/directions/{profile}/geojson
 *   POST https://api.openrouteservice.org/v2/isochrones/{profile}
 *
 * Profiles are `foot-walking` / `driving-car`, so `RoutingProfile` needs
 * mapping here — again, not above.
 */
export class OpenRouteServiceAdapter extends BaseRoutingProviderAdapter {
  readonly name = "ors" as const;
}

/** Self-hosted path, once there is a hosting budget (spec §6). OSRM's
 * `/table` service answers `getMatrix` directly and has no quota at all. */
export class SelfHostedOsrmAdapter extends BaseRoutingProviderAdapter {
  readonly name = "self_hosted_osrm" as const;
}

const ADAPTERS: Record<RoutingProviderName, () => RoutingProviderAdapter> = {
  graphhopper: () => new GraphHopperAdapter(),
  ors: () => new OpenRouteServiceAdapter(),
  self_hosted_osrm: () => new SelfHostedOsrmAdapter(),
  self_hosted_graphhopper: () => new GraphHopperAdapter(),
  self_hosted_valhalla: () => new SelfHostedOsrmAdapter(),
};

/**
 * Resolves the adapter for a city's configured provider.
 *
 * This is the provider-swap point: `cities.active_routing_provider` changes,
 * behaviour changes, no code changes (spec §2).
 */
export function createRoutingProviderAdapter(
  provider: RoutingProviderName,
): RoutingProviderAdapter {
  const factory = ADAPTERS[provider];
  if (!factory) {
    logger.warning(`Unknown routing provider ${provider}, falling back to graphhopper`);
    return new GraphHopperAdapter();
  }
  return factory();
}
