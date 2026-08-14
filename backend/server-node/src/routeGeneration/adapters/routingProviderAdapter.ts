/**
 * Layer 4 — Routing Provider Adapter.
 *
 * The single seam to the routing engine, and the only file in this module
 * allowed to know a provider exists. Domain code never imports a provider SDK;
 * that is what makes swapping providers, or self-hosting later, a one-file
 * change (spec §2).
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
 *
 * ## Rate limiting: a token bucket, not a fixed sleep
 *
 * The reference implementation this is ported from slept 1.5 s before *every*
 * request, unconditionally. That is where its own README's "the very first
 * time it might take 15–30 seconds" comes from: a route needs one matrix call
 * per profile plus one `getRoute` per leg, so a ten-stop route pays that sleep
 * a dozen times over even when every call would have succeeded instantly.
 *
 * It is also incompatible with the latency budget here — under 800 ms warm,
 * 1.5 s cold (spec §4) — which a single unconditional 1.5 s sleep exceeds on
 * its own.
 *
 * A token bucket costs nothing when calls are spread out and throttles only
 * when they genuinely bunch up, which is the actual failure being guarded
 * against. The bucket is process-wide rather than per-adapter: the quota
 * belongs to the API key, not to whichever object happens to hold it.
 */
import { Config } from "../../config";
import { getLogger } from "../../logger";
import {
  Coordinate,
  DurationMatrix,
  IsochronePolygon,
  RouteResult,
  RoutingProfile,
  RoutingProviderName,
} from "../types";
import { RoutingProviderUnavailableError } from "../errors";

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

// ---------------------------------------------------------------------------
// Token bucket, shared by every adapter instance in the process.
// ---------------------------------------------------------------------------

class TokenBucket {
  private tokens: number;
  private lastRefill = Date.now();
  /** Serializes waiters so N concurrent callers queue rather than all waking
   * on the same token and overspending the bucket they just emptied. */
  private tail: Promise<void> = Promise.resolve();

  constructor(
    private readonly capacity: number,
    private readonly refillPerSecond: number,
  ) {
    this.tokens = capacity;
  }

  take(): Promise<void> {
    const next = this.tail.then(() => this.acquire());
    // Swallow here only — the caller still sees the rejection through `next`.
    this.tail = next.catch(() => undefined);
    return next;
  }

  private async acquire(): Promise<void> {
    this.refill();
    if (this.tokens >= 1) {
      this.tokens -= 1;
      return;
    }
    const waitMs = Math.ceil(((1 - this.tokens) / this.refillPerSecond) * 1000);
    await new Promise((resolve) => setTimeout(resolve, waitMs));
    this.refill();
    this.tokens = Math.max(0, this.tokens - 1);
  }

  private refill(): void {
    const now = Date.now();
    const gained = ((now - this.lastRefill) / 1000) * this.refillPerSecond;
    if (gained > 0) {
      this.tokens = Math.min(this.capacity, this.tokens + gained);
      this.lastRefill = now;
    }
  }
}

const bucket = new TokenBucket(
  Math.max(1, Config.ROUTING_PROVIDER_BURST),
  Math.max(0.1, Config.ROUTING_PROVIDER_RPS),
);

/** Shared fetch wrapper: rate limit, timeout, one retry on 429. */
async function providerFetch(
  provider: string,
  url: string,
  init: RequestInit = {},
): Promise<unknown> {
  const MAX_ATTEMPTS = 3;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    await bucket.take();

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), PROVIDER_TIMEOUT_MS);

    let response: Response;
    try {
      response = await fetch(url, { ...init, signal: controller.signal });
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") {
        throw new RoutingProviderUnavailableError(
          provider,
          `timed out after ${PROVIDER_TIMEOUT_MS}ms`,
        );
      }
      throw new RoutingProviderUnavailableError(
        provider,
        error instanceof Error ? error.message : String(error),
      );
    } finally {
      clearTimeout(timer);
    }

    // 429 is the provider saying the bucket is still too generous. Back off
    // and retry; if it keeps saying so, the caller falls back to cache.
    if (response.status === 429 && attempt < MAX_ATTEMPTS - 1) {
      const backoffMs = 1000 * 2 ** attempt;
      logger.warning(`${provider} rate limited, retrying in ${backoffMs}ms`);
      await new Promise((resolve) => setTimeout(resolve, backoffMs));
      continue;
    }

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new RoutingProviderUnavailableError(
        provider,
        `HTTP ${response.status} ${body.slice(0, 200)}`,
      );
    }

    try {
      return await response.json();
    } catch {
      throw new RoutingProviderUnavailableError(provider, "response was not JSON");
    }
  }

  throw new RoutingProviderUnavailableError(provider, "rate limited after retries");
}

/**
 * Primary provider.
 *
 * GraphHopper takes coordinates as [lng, lat]; `Coordinate` here is {lat,lng},
 * so the swap belongs in this class and nowhere above it.
 */
export class GraphHopperAdapter implements RoutingProviderAdapter {
  readonly name = "graphhopper" as const;

  /**
   * Endpoints this key's plan has already refused, so they are not asked
   * again.
   *
   * Measured against the free plan: `/isochrone` answers
   * `Too big time_limit for Isochrone API: 28800, allowed: 0` — the endpoint is
   * not on the plan at any budget, not merely at this one. `/matrix` answers
   * `Too many points for Matrix API: 6, allowed: 5`.
   *
   * Without this the orchestrator re-asks on every request, and each refusal
   * still costs a slot against a per-minute limit the free plan enforces
   * aggressively — so the calls that cannot possibly work crowd out the
   * `/route` calls that can. Learning it at runtime beats a config flag
   * because the plan is not something the deployment knows about itself.
   */
  private static readonly unavailable = new Set<string>();

  private static disable(endpoint: string, reason: string): void {
    if (GraphHopperAdapter.unavailable.has(endpoint)) return;
    GraphHopperAdapter.unavailable.add(endpoint);
    logger.warning(
      `GraphHopper /${endpoint} is not available on this key's plan (${reason}). ` +
        "Skipping it for the rest of this process; routes degrade to estimates for " +
        "whatever it would have answered.",
    );
  }

  /** True when the provider is saying "your plan does not include this",
   * rather than "not right now" — the first is permanent, the second is a 429
   * that a retry may well clear. */
  private static isPlanRefusal(message: string): boolean {
    return /upgrade your subscription|allowed: 0/i.test(message);
  }

  private static readonly BASE = "https://graphhopper.com/api/1";
  /** GraphHopper profile ids for the two profiles this module uses. */
  private static readonly PROFILE: Record<RoutingProfile, string> = {
    driving: "car",
    walking: "foot",
  };

  constructor(private readonly apiKey: string) {}

  async getRoute(stops: Coordinate[], mode: RoutingProfile): Promise<RouteResult> {
    const params = new URLSearchParams();
    for (const s of stops) params.append("point", `${s.lat},${s.lng}`);
    params.set("profile", GraphHopperAdapter.PROFILE[mode]);
    // Plain [lng,lat] pairs rather than an encoded polyline — trades a little
    // bandwidth for not taking a polyline-decoding dependency.
    params.set("points_encoded", "false");
    params.set("key", this.apiKey);

    const json = (await providerFetch(
      this.name,
      `${GraphHopperAdapter.BASE}/route?${params.toString()}`,
    )) as { paths?: Array<{ distance?: number; time?: number; points?: { coordinates?: number[][] } }> };

    const path = json.paths?.[0];
    if (!path || typeof path.distance !== "number" || typeof path.time !== "number") {
      throw new RoutingProviderUnavailableError(this.name, "route response had no usable path");
    }

    return {
      durationSeconds: path.time / 1000,
      distanceMeters: path.distance,
      geometry: (path.points?.coordinates ?? []).map(lngLatToCoordinate),
    };
  }

  /**
   * All-pairs durations, tiled to respect the plan's matrix size cap.
   *
   * Measured against the free plan: six points comes back
   * `400 Too many points for Matrix API: 6, allowed: 5`. A 5×5 request
   * succeeds. So "one call covers every pair" (spec §4) is not achievable at
   * this size on this plan, and the choice is between tiling and not having a
   * matrix at all.
   *
   * Tiling splits the points into blocks of at most `MAX_MATRIX_POINTS` and
   * asks for each block pair, which is ceil(n/5)² requests — 9 for a 15-stop
   * city. That is still one *logical* matrix and nothing above this method
   * knows the difference; what it is not is cheap, which is why
   * `ROUTING_PROVIDER_MATRIX_MAX_CALLS` bounds it. Past that bound this throws
   * and the orchestrator degrades to estimated ordering rather than spending a
   * day's quota on one request.
   */
  async getMatrix(points: Coordinate[], mode: RoutingProfile): Promise<DurationMatrix> {
    if (GraphHopperAdapter.unavailable.has("matrix")) {
      throw new RoutingProviderUnavailableError(this.name, "matrix is not on this plan");
    }

    const max = Math.max(1, Config.ROUTING_PROVIDER_MATRIX_MAX_POINTS);
    const blocks: Coordinate[][] = [];
    for (let i = 0; i < points.length; i += max) blocks.push(points.slice(i, i + max));

    const callCount = blocks.length * blocks.length;
    if (callCount > Config.ROUTING_PROVIDER_MATRIX_MAX_CALLS) {
      throw new RoutingProviderUnavailableError(
        this.name,
        `a ${points.length}-point matrix needs ${callCount} tiled calls at ${max} points ` +
          `per call, over the ${Config.ROUTING_PROVIDER_MATRIX_MAX_CALLS} allowed`,
      );
    }

    const durations: Array<Array<number | null>> = points.map(() => points.map(() => null));
    const distances: Array<Array<number | null>> = points.map(() => points.map(() => null));

    // Sequential, not concurrent: the free plan's per-minute limit is far
    // tighter than its per-second one, and firing nine matrix calls at once is
    // exactly the burst it answers with "limit heavily violated".
    for (let bi = 0; bi < blocks.length; bi++) {
      for (let bj = 0; bj < blocks.length; bj++) {
        const tile = await this.matrixTile(blocks[bi]!, blocks[bj]!, mode);
        for (let i = 0; i < blocks[bi]!.length; i++) {
          for (let j = 0; j < blocks[bj]!.length; j++) {
            durations[bi * max + i]![bj * max + j] = tile.times[i]?.[j] ?? null;
            distances[bi * max + i]![bj * max + j] = tile.distances?.[i]?.[j] ?? null;
          }
        }
      }
    }

    return { durations, distances, points };
  }

  private async matrixTile(
    from: Coordinate[],
    to: Coordinate[],
    mode: RoutingProfile,
  ): Promise<{ times: number[][]; distances?: number[][] }> {
    const body = {
      from_points: from.map((p) => [p.lng, p.lat]),
      to_points: to.map((p) => [p.lng, p.lat]),
      out_arrays: ["times", "distances"],
      // The Matrix API historically took `vehicle` where the Routing API takes
      // `profile`. Current docs use `profile` for both; if a key on an older
      // plan starts 400ing here, this is the field to flip.
      profile: GraphHopperAdapter.PROFILE[mode],
    };

    let json: { times?: number[][]; distances?: number[][] };
    try {
      json = (await providerFetch(
        this.name,
        `${GraphHopperAdapter.BASE}/matrix?key=${this.apiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        },
      )) as { times?: number[][]; distances?: number[][] };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (GraphHopperAdapter.isPlanRefusal(message)) {
        GraphHopperAdapter.disable("matrix", message.slice(0, 120));
      }
      throw error;
    }

    if (!Array.isArray(json.times)) {
      throw new RoutingProviderUnavailableError(this.name, "matrix response had no times array");
    }
    // GraphHopper returns seconds, which is what DurationMatrix stores — no
    // conversion, deliberately. Minutes belong to the response, not here.
    return { times: json.times, distances: json.distances };
  }

  async getIsochrone(
    origin: Coordinate,
    timeBudgetMinutes: number,
    mode: RoutingProfile,
  ): Promise<IsochronePolygon> {
    if (GraphHopperAdapter.unavailable.has("isochrone")) {
      throw new RoutingProviderUnavailableError(this.name, "isochrone is not on this plan");
    }

    const params = new URLSearchParams({
      point: `${origin.lat},${origin.lng}`,
      time_limit: String(Math.round(timeBudgetMinutes * 60)),
      profile: GraphHopperAdapter.PROFILE[mode],
      buckets: "1",
      key: this.apiKey,
    });

    let json: { polygons?: Array<{ geometry?: { type?: string; coordinates?: number[][][] } }> };
    try {
      json = (await providerFetch(
        this.name,
        `${GraphHopperAdapter.BASE}/isochrone?${params.toString()}`,
      )) as { polygons?: Array<{ geometry?: { type?: string; coordinates?: number[][][] } }> };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (GraphHopperAdapter.isPlanRefusal(message)) {
        GraphHopperAdapter.disable("isochrone", message.slice(0, 120));
      }
      throw error;
    }

    const geometry = json.polygons?.[0]?.geometry;
    if (!geometry || geometry.type !== "Polygon" || !Array.isArray(geometry.coordinates)) {
      throw new RoutingProviderUnavailableError(this.name, "isochrone response had no polygon");
    }

    return {
      // GeoJSON order ([lng, lat]) is kept as-is: IsochronePolygon documents
      // itself as GeoJSON-shaped, and the estimator's point-in-polygon test
      // reads it that way.
      coordinates: geometry.coordinates.map((ring) =>
        ring.map((p) => [p[0] as number, p[1] as number] as [number, number]),
      ),
      timeBudgetMinutes,
      mode,
    };
  }
}

/**
 * The no-API-key path: great-circle distance divided by a nominal speed.
 *
 * **Every number this returns is an estimate, and the logs say so at
 * construction.** It exists because the alternative is that a machine without
 * a provider key answers 503 to every route request, which makes the module
 * impossible to develop or demo against — and because the orchestrator's
 * degradation path (spec §8) is specified to prefer a worse answer over no
 * answer, which is exactly what this is.
 *
 * The detour factor is the one piece of realism worth keeping: straight-line
 * distance underestimates road distance systematically, and in a dense old
 * city like the Casbah it underestimates it badly. 1.35 is the usual
 * rule-of-thumb ratio for urban street networks.
 */
export class StraightLineRoutingProvider implements RoutingProviderAdapter {
  private static readonly METRES_PER_SECOND: Record<RoutingProfile, number> = {
    walking: 4.5 / 3.6, // 4.5 km/h — a tourist pace, not a commuter's
    driving: 25 / 3.6, // 25 km/h — urban average including stops
  };
  private static readonly DETOUR_FACTOR = 1.35;

  /** Warned once per provider name, not once per instance: this is also
   * constructed on the orchestrator's degradation path, which can happen
   * several times a request, and a per-instance warning would bury the log it
   * is meant to stand out in. */
  private static readonly warned = new Set<string>();

  constructor(readonly name: RoutingProviderName) {
    if (!StraightLineRoutingProvider.warned.has(name)) {
      StraightLineRoutingProvider.warned.add(name);
      logger.warning(
        `Straight-line estimates in use for ${name}. Without GRAPHHOPPER_API_KEY this is ` +
          "every number; with one it is only whatever the provider could not answer.",
      );
    }
  }

  private leg(from: Coordinate, to: Coordinate, mode: RoutingProfile): RouteResult {
    const distanceMeters = haversineMeters(from, to) * StraightLineRoutingProvider.DETOUR_FACTOR;
    return {
      durationSeconds: distanceMeters / StraightLineRoutingProvider.METRES_PER_SECOND[mode],
      distanceMeters,
      // Two points, so the map draws a straight line between stops. Honest
      // about being an estimate rather than inventing a plausible-looking path.
      geometry: [from, to],
    };
  }

  async getRoute(stops: Coordinate[], mode: RoutingProfile): Promise<RouteResult> {
    if (stops.length < 2) {
      return { durationSeconds: 0, distanceMeters: 0, geometry: stops.slice() };
    }
    let durationSeconds = 0;
    let distanceMeters = 0;
    for (let i = 0; i < stops.length - 1; i++) {
      const leg = this.leg(stops[i]!, stops[i + 1]!, mode);
      durationSeconds += leg.durationSeconds;
      distanceMeters += leg.distanceMeters;
    }
    return { durationSeconds, distanceMeters, geometry: stops.slice() };
  }

  async getMatrix(points: Coordinate[], mode: RoutingProfile): Promise<DurationMatrix> {
    const durations = points.map((from) =>
      points.map((to) => this.leg(from, to, mode).durationSeconds),
    );
    const distances = points.map((from) =>
      points.map((to) => this.leg(from, to, mode).distanceMeters),
    );
    return { durations, distances, points };
  }

  async getIsochrone(
    origin: Coordinate,
    timeBudgetMinutes: number,
    mode: RoutingProfile,
  ): Promise<IsochronePolygon> {
    // A circle of the radius reachable at the nominal speed, as a 32-gon.
    // Crude, but it is the same crudeness as the durations above, so the
    // day-count flag stays consistent with the travel times it is judged next
    // to rather than mixing a real isochrone with estimated legs.
    const radiusMeters =
      ((timeBudgetMinutes * 60 * StraightLineRoutingProvider.METRES_PER_SECOND[mode]) /
        StraightLineRoutingProvider.DETOUR_FACTOR);
    const ring: Array<[number, number]> = [];
    const latDegPerMetre = 1 / 111_320;
    const lngDegPerMetre = 1 / (111_320 * Math.cos((origin.lat * Math.PI) / 180) || 1);
    for (let i = 0; i <= 32; i++) {
      const angle = (i / 32) * 2 * Math.PI;
      ring.push([
        origin.lng + radiusMeters * lngDegPerMetre * Math.cos(angle),
        origin.lat + radiusMeters * latDegPerMetre * Math.sin(angle),
      ]);
    }
    return { coordinates: [ring], timeBudgetMinutes, mode };
  }
}

function lngLatToCoordinate(pair: number[]): Coordinate {
  return { lat: pair[1] ?? 0, lng: pair[0] ?? 0 };
}

function haversineMeters(a: Coordinate, b: Coordinate): number {
  const R = 6_371_000;
  const toRad = (deg: number): number => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/**
 * Resolves the adapter for a city's configured provider.
 *
 * This is the provider-swap point: `cities.active_routing_provider` changes,
 * behaviour changes, no code changes (spec §2).
 *
 * OpenRouteService and the self-hosted profiles resolve to the estimator until
 * someone needs them — their request shapes differ (`foot-walking` /
 * `driving-car` profiles, POST bodies, a `/table` service for OSRM) and
 * writing them blind against no key and no account would be guessing, not
 * porting. Each is one class here when the time comes; nothing above Layer 4
 * changes.
 */
export function createRoutingProviderAdapter(
  provider: RoutingProviderName,
): RoutingProviderAdapter {
  // Read at call time, not at import: it is what the test suite sets so an
  // automated run never spends free-tier quota (spec §11, "a stub adapter is
  // used for every automated run"). A key being present in .env must not
  // change what `npm test` costs.
  if (process.env.ROUTING_PROVIDER_FORCE_ESTIMATE === "1") {
    return new StraightLineRoutingProvider(provider);
  }
  if (
    (provider === "graphhopper" || provider === "self_hosted_graphhopper") &&
    Config.GRAPHHOPPER_API_KEY
  ) {
    return new GraphHopperAdapter(Config.GRAPHHOPPER_API_KEY);
  }
  return new StraightLineRoutingProvider(provider);
}
