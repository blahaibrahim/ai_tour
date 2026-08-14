import { Redis } from 'ioredis';

/**
 * Small factory so client construction (retry policy, connection
 * lifecycle) lives in one place. The composition root (driver script /
 * Orchestration wiring, Steps 5–6) calls this once and passes the
 * resulting client into RedisCacheAdapter — the adapter itself never
 * constructs or owns its own connection, which keeps it trivially
 * testable with any Redis-shaped client (see redis-cache.adapter.test.ts).
 */
export function createRedisClient(url: string): Redis {
  return new Redis(url, {
    maxRetriesPerRequest: 3,
  });
}
