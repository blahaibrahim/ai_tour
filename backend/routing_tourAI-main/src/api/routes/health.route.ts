import type { FastifyInstance } from 'fastify';
import type { AppDependencies } from '../composition-root.js';

export function registerHealthRoute(app: FastifyInstance, deps: AppDependencies) {
  app.get('/health', async (_request, _reply) => {
    let redisStatus = 'not_configured';
    if (deps.redisClient) {
      try {
        await deps.redisClient.ping();
        redisStatus = 'connected';
      } catch {
        redisStatus = 'disconnected';
      }
    }

    return {
      status: 'ok',
      uptime: process.uptime(),
      redis: redisStatus,
      cities: (await Promise.all(
        ['Algiers', 'Oran', 'Constantine'].map((n) => deps.cityConfigRepository.findByName(n)),
      )).filter(Boolean).length,
      timestamp: new Date().toISOString(),
    };
  });
}
