import Fastify, { type FastifyInstance } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { loadEnv, type Env } from '../config/env.js';
import { GraphHopperAdapter } from '../adapters/routing-provider/graphhopper.adapter.js';
import { MockRoutingProviderAdapter } from '../../tests/fixtures/mock-routing-provider.adapter.js';
import { InMemoryCacheAdapter } from '../adapters/cache/in-memory-cache.adapter.js';
import { RedisCacheAdapter } from '../adapters/cache/redis-cache.adapter.js';
import { createRedisClient } from '../adapters/cache/redis-client.js';
import { InMemoryPoiRepository } from '../data/repositories/poi.repository.js';
import { InMemoryCityConfigRepository } from '../data/repositories/city-config.repository.js';
import { InMemoryRouteRepository } from '../data/repositories/route.repository.js';
import { PgPoiRepository } from '../data/repositories/pg-poi.repository.js';
import { PgCityConfigRepository } from '../data/repositories/pg-city-config.repository.js';
import { PgRouteRepository } from '../data/repositories/pg-route.repository.js';
import { createDbClient } from '../data/db/client.js';
import type { Kysely } from 'kysely';
import type { DB } from '../data/db/types.js';
import type { PoiRepository } from '../domain/ports/poi-repository.port.js';
import type { CityConfigRepository } from '../domain/ports/city-config-repository.port.js';
import type { RouteRepository } from '../domain/ports/route-repository.port.js';
import { PoiSelector } from '../domain/services/poi-selector/index.js';
import { RouteGenerationOrchestrator } from '../orchestration/route-generation.orchestrator.js';
import {
  ALL_CITY_CONFIGS,
  ALL_FIXTURE_POIS,
  THEME_CATEGORY_MAP,
} from '../data/fixtures/index.js';
import type { RoutingProviderAdapter } from '../domain/ports/routing-provider-adapter.port.js';
import type { CacheAdapter } from '../domain/ports/cache-adapter.port.js';
import type { Redis } from 'ioredis';
import { registerHealthRoute } from './routes/health.route.js';
import { registerRouteGenerationRoute } from './routes/route-generation.route.js';
import { registerCitiesRoutes } from './routes/cities.route.js';
import { registerPoisRoute } from './routes/pois.route.js';
import { registerErrorHandler } from './plugins/error-handler.js';

export interface AppDependencies {
  orchestrator: RouteGenerationOrchestrator;
  cityConfigRepository: CityConfigRepository;
  poiRepository: PoiRepository;
  routeRepository: RouteRepository;
  cache: CacheAdapter;
  redisClient: Redis | null;
  dbClient: Kysely<DB> | null;
}

/**
 * Production composition root. Wires all dependencies based on
 * environment configuration and returns a ready-to-listen Fastify
 * instance.
 *
 * - Uses GraphHopper adapter if API key is set; falls back to mock.
 * - Uses Redis cache if REDIS_URL connects successfully; falls back
 *   to in-memory.
 * - Uses in-memory repositories with fixture data (real DB repositories
 *   swap in behind the same ports once the Data layer migrations run).
 */
export async function createApp(envOverrides?: Partial<Env>): Promise<{
  app: FastifyInstance;
  deps: AppDependencies;
}> {
  const env = { ...loadEnv(), ...envOverrides };

  const app = Fastify({
    logger: {
      level: 'info',
      ...(process.env.NODE_ENV !== 'production'
        ? { transport: { target: 'pino-pretty', options: { translateTime: 'HH:MM:ss', ignore: 'pid,hostname' } } }
        : {}),
    },
  }) as unknown as FastifyInstance;

  // ── Rate limiting (Section 3: "rate-limits") ────────────────────────
  await app.register(rateLimit, {
    max: 30,
    timeWindow: '1 minute',
  });

  // ── Routing provider ────────────────────────────────────────────────
  let routingProvider: RoutingProviderAdapter;
  if (env.ROUTING_PROVIDER_GRAPHHOPPER_API_KEY) {
    routingProvider = new GraphHopperAdapter({
      apiKey: env.ROUTING_PROVIDER_GRAPHHOPPER_API_KEY,
      timeoutMs: env.ROUTING_PROVIDER_TIMEOUT_MS,
    });
    app.log.info('Routing provider: GraphHopper (live API)');
  } else {
    routingProvider = new MockRoutingProviderAdapter();
    app.log.warn('Routing provider: MOCK (no ROUTING_PROVIDER_GRAPHHOPPER_API_KEY set)');
  }

  // ── Cache ───────────────────────────────────────────────────────────
  let cache: CacheAdapter;
  let redisClient: Redis | null = null;

  try {
    redisClient = createRedisClient(env.REDIS_URL);
    // Test connection with a short timeout
    await Promise.race([
      redisClient.ping(),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Redis connection timeout')), 3000),
      ),
    ]);
    cache = new RedisCacheAdapter({ client: redisClient });
    app.log.info('Cache: Redis (%s)', env.REDIS_URL);
  } catch (err) {
    app.log.warn('Cache: in-memory fallback (Redis unavailable: %s)', (err as Error).message);
    if (redisClient) {
      redisClient.disconnect();
      redisClient = null;
    }
    cache = new InMemoryCacheAdapter();
  }

  // ── Repositories (Postgres with fixture fallback) ──────────────────
  let dbClient: Kysely<DB> | null = null;
  let poiRepository: PoiRepository;
  let cityConfigRepository: CityConfigRepository;
  let routeRepository: RouteRepository;

  try {
    dbClient = createDbClient(env.DATABASE_URL);
    // Simple query to verify connection
    await dbClient.selectFrom('cities').select('id').limit(1).execute();
    
    poiRepository = new PgPoiRepository(dbClient);
    cityConfigRepository = new PgCityConfigRepository(dbClient);
    routeRepository = new PgRouteRepository(dbClient);
    app.log.info('Repositories: PostgreSQL (Kysely)');
  } catch (err) {
    app.log.warn('Repositories: in-memory fallback (PostgreSQL unavailable: %s)', (err as Error).message);
    if (dbClient) {
      await dbClient.destroy();
      dbClient = null;
    }
    poiRepository = new InMemoryPoiRepository(ALL_FIXTURE_POIS);
    cityConfigRepository = new InMemoryCityConfigRepository(ALL_CITY_CONFIGS);
    routeRepository = new InMemoryRouteRepository();
  }

  // ── Domain services ────────────────────────────────────────────────
  const poiSelector = new PoiSelector(poiRepository, THEME_CATEGORY_MAP);

  // ── Orchestrator ───────────────────────────────────────────────────
  const orchestrator = new RouteGenerationOrchestrator({
    routingProvider,
    cache,
    cityConfigRepository,
    poiSelector,
  });

  const deps: AppDependencies = {
    orchestrator,
    cityConfigRepository,
    poiRepository,
    routeRepository,
    cache,
    redisClient,
    dbClient,
  };

  // ── Plugins & routes ───────────────────────────────────────────────
  registerErrorHandler(app);
  registerHealthRoute(app, deps);
  registerRouteGenerationRoute(app, deps);
  registerCitiesRoutes(app, deps);
  registerPoisRoute(app, deps);

  // ── Graceful shutdown ──────────────────────────────────────────────
  app.addHook('onClose', async () => {
    if (redisClient) {
      app.log.info('Closing Redis connection');
      redisClient.disconnect();
    }
    if (dbClient) {
      app.log.info('Closing Postgres connection');
      await dbClient.destroy();
    }
  });

  return { app, deps };
}
