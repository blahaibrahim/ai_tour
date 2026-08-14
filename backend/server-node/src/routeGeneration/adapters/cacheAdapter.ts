/**
 * Layer 4 — Cache Adapter.
 *
 * Checked before *every* Routing Provider Adapter call, without exception. It
 * is the primary lever on both the latency budget (under 800 ms on a cache
 * hit) and the provider quota (per-minute credits, or 2,500 requests/day) —
 * spec §2 and §10 both call the cache-first rule mandatory rather than an
 * optimization.
 *
 * STATUS: interface plus the in-memory implementation the spec's build order
 * asks for ("Cache Adapter can start as an in-memory dictionary; Redis is a
 * later swap behind the same interface" — §9 step 2). The Redis implementation
 * and the nightly warm job are stubs.
 *
 * ## Legs are cached too — NOT IN SPEC
 *
 * §7's cache interface covers matrices and isochrones only, which leaves the
 * `getRoute` calls uncached. That is the single largest source of provider
 * traffic in practice, and it is not close: a matrix is one call per profile
 * per request, while legs are one call *per hop*. A 15-stop route is two
 * matrix calls and fourteen leg calls.
 *
 * It is also the traffic that repeats most. A matrix is keyed to one exact set
 * of points, so a different theme in the same city is a different key. A leg
 * is just "from here to there on foot" — the Casbah-to-Ketchaoua walk is the
 * same leg in a history route, a culture route and an everything route, in
 * every time budget, for every traveller. Keying legs on the coordinate pair
 * rather than on anything about the request is what lets them be shared that
 * widely.
 */
import { Config } from "../../config";
import { getLogger } from "../../logger";
import { NotImplementedError } from "../errors";
import { Coordinate, DurationMatrix, IsochronePolygon, RouteResult } from "../types";

const logger = getLogger("routeGeneration.cache");

/** Spec §7, transcribed, plus the leg methods described above. */
export interface CacheAdapter {
  getMatrix(cityId: string, mode: string): Promise<DurationMatrix | null>;
  setMatrix(cityId: string, mode: string, matrix: DurationMatrix): Promise<void>;
  getIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
  ): Promise<IsochronePolygon | null>;
  setIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
    polygon: IsochronePolygon,
  ): Promise<void>;
  /** NOT IN SPEC — see the module docstring. */
  getLeg(from: Coordinate, to: Coordinate, mode: string): Promise<RouteResult | null>;
  setLeg(from: Coordinate, to: Coordinate, mode: string, leg: RouteResult): Promise<void>;
}

/**
 * A leg's cache key: the two endpoints and the profile, and nothing else.
 *
 * Deliberately carries no city, theme or route id. Those would scope the entry
 * to the request that happened to create it, and the whole value of caching a
 * leg is that the next request for the same two points — whatever route it
 * belongs to — is a hit.
 *
 * Direction is part of the key. A→B and B→A are genuinely different journeys
 * on a one-way street, and collapsing them would hand back a path that runs
 * the wrong way up it.
 *
 * Seven decimal places is ~11 mm. Coordinates come from the same POI rows
 * every time, so this is an equality check, not a proximity one.
 */
export function legKey(from: Coordinate, to: Coordinate, mode: string): string {
  const point = (c: Coordinate): string => `${c.lat.toFixed(7)},${c.lng.toFixed(7)}`;
  return `${mode}:${point(from)}>${point(to)}`;
}

/**
 * Isochrone budgets are rounded to a bucket before being used as a key.
 *
 * Without this every distinct remaining-budget value in minutes is its own
 * key, so the isochrone cache would never hit — the budget is a running
 * subtraction and effectively continuous.
 */
export const ISOCHRONE_BUCKET_MINUTES = 15;

export function isochroneBucket(minutes: number): number {
  return Math.max(
    ISOCHRONE_BUCKET_MINUTES,
    Math.round(minutes / ISOCHRONE_BUCKET_MINUTES) * ISOCHRONE_BUCKET_MINUTES,
  );
}

/** How long a cached entry is served. POI positions do not move and the road
 * network changes slowly; the nightly warm job refreshes ahead of demand. */
export const MATRIX_TTL_MS = 24 * 60 * 60 * 1000;
export const ISOCHRONE_TTL_MS = 24 * 60 * 60 * 1000;

/**
 * Legs live longer than matrices and isochrones — a week rather than a day.
 *
 * They are the most stable thing the provider returns: the walk from one
 * monument to another changes when the street layout does, which is a matter
 * of years. Matrices get the shorter life because they are keyed to a POI set
 * that genuinely does change as the catalogue is edited, and isochrones
 * because they are the most sensitive to traffic modelling.
 */
export const LEG_TTL_MS = 7 * 24 * 60 * 60 * 1000;

interface Entry<T> {
  value: T;
  storedAt: number;
}

/**
 * The starting implementation. Process-local, so it is per-instance rather
 * than shared — which is correct for a single deployable service and is
 * exactly what the Redis swap later fixes.
 */
export class InMemoryCacheAdapter implements CacheAdapter {
  private readonly matrices = new Map<string, Entry<DurationMatrix>>();
  private readonly isochrones = new Map<string, Entry<IsochronePolygon>>();
  private readonly legs = new Map<string, Entry<RouteResult>>();

  /** Counted so a cache hit skipping the adapter call is assertable rather
   * than assumed — one of the spec's named test cases (§11). */
  readonly stats = { legHits: 0, legMisses: 0 };

  private static fresh<T>(entry: Entry<T> | undefined, ttlMs: number): T | null {
    if (!entry) return null;
    if (Date.now() - entry.storedAt > ttlMs) return null;
    return entry.value;
  }

  async getMatrix(cityId: string, mode: string): Promise<DurationMatrix | null> {
    return InMemoryCacheAdapter.fresh(this.matrices.get(`${cityId}:${mode}`), MATRIX_TTL_MS);
  }

  async setMatrix(cityId: string, mode: string, matrix: DurationMatrix): Promise<void> {
    this.matrices.set(`${cityId}:${mode}`, { value: matrix, storedAt: Date.now() });
  }

  async getIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
  ): Promise<IsochronePolygon | null> {
    return InMemoryCacheAdapter.fresh(
      this.isochrones.get(`${poiId}:${timeBucket}:${mode}`),
      ISOCHRONE_TTL_MS,
    );
  }

  async setIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
    polygon: IsochronePolygon,
  ): Promise<void> {
    this.isochrones.set(`${poiId}:${timeBucket}:${mode}`, {
      value: polygon,
      storedAt: Date.now(),
    });
  }

  async getLeg(from: Coordinate, to: Coordinate, mode: string): Promise<RouteResult | null> {
    const hit = InMemoryCacheAdapter.fresh(this.legs.get(legKey(from, to, mode)), LEG_TTL_MS);
    if (hit) this.stats.legHits++;
    else this.stats.legMisses++;
    return hit;
  }

  async setLeg(
    from: Coordinate,
    to: Coordinate,
    mode: string,
    leg: RouteResult,
  ): Promise<void> {
    this.legs.set(legKey(from, to, mode), { value: leg, storedAt: Date.now() });
  }

  /** Test hook — asserting a cache hit skips the Adapter call entirely is one
   * of the spec's named test cases (§11). */
  clear(): void {
    this.matrices.clear();
    this.isochrones.clear();
    this.legs.clear();
    this.stats.legHits = 0;
    this.stats.legMisses = 0;
  }
}

/**
 * The durable swap. Same interface, so nothing above Layer 4 changes.
 *
 * What Redis buys over the in-memory adapter is not speed — a Map is faster —
 * but **survival**. The in-memory cache dies with the process, so every deploy,
 * restart and crash starts cold, and on a rate-limited provider plan the first
 * route after a restart is the expensive one. It is also per-instance, so two
 * replicas each pay for the same legs.
 *
 * Keys are prefixed `route-gen:` because Redis is routinely shared across
 * services and environments; the in-memory adapter needs no prefix since its
 * Map is already scoped to one process.
 *
 * Only the two commands are used — GET and SET-with-expiry — so this works
 * unchanged against a local container, Redis Cloud, or Upstash.
 */
export class RedisCacheAdapter implements CacheAdapter {
  /** Narrow on purpose: anything with these two methods can stand in, which
   * is what keeps this testable without a server. */
  constructor(
    private readonly client: {
      get(key: string): Promise<string | null>;
      set(key: string, value: string, mode: "EX", seconds: number): Promise<unknown>;
    },
  ) {}

  private async read<T>(key: string): Promise<T | null> {
    const raw = await this.client.get(key);
    if (raw === null) return null;
    try {
      return JSON.parse(raw) as T;
    } catch {
      // A value that will not parse is a value from an older shape of this
      // code. Treated as a miss and left to expire rather than thrown, so a
      // format change degrades to a cold cache instead of an outage.
      logger.warning(`Redis: discarding unparseable entry at ${key}`);
      return null;
    }
  }

  private async write(key: string, value: unknown, ttlMs: number): Promise<void> {
    await this.client.set(key, JSON.stringify(value), "EX", Math.ceil(ttlMs / 1000));
  }

  getMatrix(cityId: string, mode: string): Promise<DurationMatrix | null> {
    return this.read<DurationMatrix>(`route-gen:matrix:${cityId}:${mode}`);
  }

  setMatrix(cityId: string, mode: string, matrix: DurationMatrix): Promise<void> {
    return this.write(`route-gen:matrix:${cityId}:${mode}`, matrix, MATRIX_TTL_MS);
  }

  getIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
  ): Promise<IsochronePolygon | null> {
    return this.read<IsochronePolygon>(`route-gen:isochrone:${poiId}:${timeBucket}:${mode}`);
  }

  setIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
    polygon: IsochronePolygon,
  ): Promise<void> {
    return this.write(
      `route-gen:isochrone:${poiId}:${timeBucket}:${mode}`,
      polygon,
      ISOCHRONE_TTL_MS,
    );
  }

  getLeg(from: Coordinate, to: Coordinate, mode: string): Promise<RouteResult | null> {
    return this.read<RouteResult>(`route-gen:leg:${legKey(from, to, mode)}`);
  }

  setLeg(from: Coordinate, to: Coordinate, mode: string, leg: RouteResult): Promise<void> {
    return this.write(`route-gen:leg:${legKey(from, to, mode)}`, leg, LEG_TTL_MS);
  }
}

/**
 * Redis in front, memory behind, and a failure in the first is never a failure
 * of the request.
 *
 * The reference implementation picks its backend once at boot and commits: if
 * Redis dies an hour later, every cache read throws, and the orchestrator's
 * `cache.getMatrix` call is not inside its try block — so a cache outage
 * becomes a 500 on a request that could have been answered by simply asking
 * the provider.
 *
 * That is the wrong failure mode for a cache. Everything in here is
 * recomputable by definition, so an unreachable Redis should cost latency and
 * quota, nothing else. Reads fall through to the in-memory layer; writes go to
 * both, so the process keeps a warm local copy either way and stops depending
 * on Redis being back.
 */
export class ResilientCacheAdapter implements CacheAdapter {
  private readonly fallback = new InMemoryCacheAdapter();
  private warned = false;

  constructor(private readonly primary: CacheAdapter) {}

  /** Logged once, not per operation: a Redis outage produces one of these per
   * cache call, and a few thousand identical lines would bury the rest of the
   * request log. */
  private degrade(operation: string, error: unknown): void {
    if (this.warned) return;
    this.warned = true;
    logger.warning(
      `Redis ${operation} failed (${error instanceof Error ? error.message : error}) — ` +
        "serving the route cache from memory until it recovers",
    );
  }

  async getMatrix(cityId: string, mode: string): Promise<DurationMatrix | null> {
    try {
      const hit = await this.primary.getMatrix(cityId, mode);
      if (hit) return hit;
    } catch (error) {
      this.degrade("getMatrix", error);
    }
    return this.fallback.getMatrix(cityId, mode);
  }

  async setMatrix(cityId: string, mode: string, matrix: DurationMatrix): Promise<void> {
    await this.fallback.setMatrix(cityId, mode, matrix);
    try {
      await this.primary.setMatrix(cityId, mode, matrix);
    } catch (error) {
      this.degrade("setMatrix", error);
    }
  }

  async getIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
  ): Promise<IsochronePolygon | null> {
    try {
      const hit = await this.primary.getIsochrone(poiId, timeBucket, mode);
      if (hit) return hit;
    } catch (error) {
      this.degrade("getIsochrone", error);
    }
    return this.fallback.getIsochrone(poiId, timeBucket, mode);
  }

  async setIsochrone(
    poiId: string,
    timeBucket: number,
    mode: string,
    polygon: IsochronePolygon,
  ): Promise<void> {
    await this.fallback.setIsochrone(poiId, timeBucket, mode, polygon);
    try {
      await this.primary.setIsochrone(poiId, timeBucket, mode, polygon);
    } catch (error) {
      this.degrade("setIsochrone", error);
    }
  }

  async getLeg(from: Coordinate, to: Coordinate, mode: string): Promise<RouteResult | null> {
    try {
      const hit = await this.primary.getLeg(from, to, mode);
      if (hit) return hit;
    } catch (error) {
      this.degrade("getLeg", error);
    }
    return this.fallback.getLeg(from, to, mode);
  }

  async setLeg(
    from: Coordinate,
    to: Coordinate,
    mode: string,
    leg: RouteResult,
  ): Promise<void> {
    await this.fallback.setLeg(from, to, mode, leg);
    try {
      await this.primary.setLeg(from, to, mode, leg);
    } catch (error) {
      this.degrade("setLeg", error);
    }
  }
}

let shared: CacheAdapter | null = null;

/**
 * Chooses the cache backend. Called once at server boot, before any request.
 *
 * Async because deciding requires a round trip, while `getCacheAdapter()` is
 * called from inside the pipeline and must stay synchronous. Doing the probe
 * here rather than lazily on first use also means the answer — and the reason
 * for it — is in the startup log rather than buried in whichever request
 * happened to be first.
 *
 * Safe to skip entirely: without `REDIS_URL`, or if the probe fails, this is
 * exactly the behaviour that existed before Redis was an option.
 */
export async function initCache(): Promise<CacheAdapter> {
  if (!Config.REDIS_URL) {
    shared = new InMemoryCacheAdapter();
    logger.info(
      "Cache: in-memory (no REDIS_URL). Warm entries are lost on restart — " +
        "set REDIS_URL to keep them.",
    );
    return shared;
  }

  const { createRedisClient } = await import("./redisClient");
  const client = createRedisClient(Config.REDIS_URL);

  try {
    // Bounded: a Redis that never answers must not hold up server startup.
    await Promise.race([
      client.ping(),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("ping timed out after 3000ms")), 3_000),
      ),
    ]);
    shared = new ResilientCacheAdapter(new RedisCacheAdapter(client));
    logger.info(`Cache: Redis at ${redactUrl(Config.REDIS_URL)} (in-memory fallback behind it)`);
  } catch (error) {
    client.disconnect();
    shared = new InMemoryCacheAdapter();
    logger.warning(
      `Cache: in-memory — Redis at ${redactUrl(Config.REDIS_URL)} did not answer ` +
        `(${error instanceof Error ? error.message : error})`,
    );
  }

  return shared;
}

/** Redis URLs routinely carry a password. */
function redactUrl(url: string): string {
  try {
    const parsed = new URL(url);
    if (parsed.password) parsed.password = "***";
    return parsed.toString();
  } catch {
    return "the configured URL";
  }
}

export function getCacheAdapter(): CacheAdapter {
  // Falls back to in-memory rather than throwing when `initCache` has not run
  // — scripts and tests call into the pipeline without booting a server, and
  // making them all remember to initialise a cache would be ceremony for no
  // safety.
  if (shared === null) shared = new InMemoryCacheAdapter();
  return shared;
}

/** Test hook — lets a test install a known cache and put it back afterwards. */
export function setCacheAdapter(adapter: CacheAdapter | null): void {
  shared = adapter;
}

/**
 * Nightly scheduled job: refreshes each *active* city's full POI matrix ahead
 * of demand, so the first user request of the day is a cache hit rather than
 * the one that pays for the cold matrix (spec §8).
 *
 * STATUS: stub. Needs the POI repository and the routing adapter first.
 */
export async function warmActiveCityMatrices(): Promise<void> {
  throw new NotImplementedError("warmActiveCityMatrices (nightly matrix warm job)");
}
