/**
 * Redis connection factory for the route-generation cache.
 *
 * One place for connection policy so `RedisCacheAdapter` never constructs or
 * owns a connection — it takes a client, the same dependency-injection shape
 * `GraphHopperAdapter` uses for its key, and stays testable against anything
 * with the two methods it calls.
 *
 * ## Why the retry policy is this conservative
 *
 * A cache is not a database. Every value in it can be recomputed by asking the
 * routing provider again, so an unreachable Redis must degrade to a slower
 * request, never a failed one — and certainly never a *hung* one. ioredis's
 * defaults are tuned for a primary datastore: unlimited reconnection attempts
 * and commands queued indefinitely while offline, which for us would mean a
 * route request blocking on a cache lookup that will never answer.
 *
 * So: bounded retries, a short connect timeout, and `enableOfflineQueue:false`
 * to make commands fail fast while disconnected rather than pile up. The
 * resilient wrapper in `cacheAdapter.ts` turns those fast failures into
 * in-memory reads.
 */
import { Redis } from "ioredis";

import { getLogger } from "../../logger";

const logger = getLogger("routeGeneration.redis");

export function createRedisClient(url: string): Redis {
  const client = new Redis(url, {
    // Bounded, so a command against a dead Redis gives up instead of retrying
    // inside the request that is waiting for it.
    maxRetriesPerRequest: 2,
    connectTimeout: 3_000,
    // Fail immediately while disconnected rather than queueing. The caller
    // has a working in-memory fallback; a queued command it never sees is
    // worse than an error it can handle.
    enableOfflineQueue: false,
    // Give up reconnecting after a while instead of retrying forever at
    // increasing intervals for the life of the process.
    retryStrategy: (times) => (times > 10 ? null : Math.min(times * 200, 2_000)),
  });

  // ioredis emits 'error' on every failed reconnection attempt. Without a
  // listener Node treats it as an unhandled 'error' event and kills the
  // process — a cache being unreachable must not do that.
  client.on("error", (error: Error) => {
    logger.warning(`Redis: ${error.message}`);
  });
  client.on("end", () => {
    logger.warning("Redis connection closed — cache falls back to in-memory");
  });

  return client;
}
