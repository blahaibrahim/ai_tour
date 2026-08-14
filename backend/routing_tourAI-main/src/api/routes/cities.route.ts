import type { FastifyInstance } from 'fastify';
import type { AppDependencies } from '../composition-root.js';
import { ALL_CITY_CONFIGS } from '../../data/fixtures/index.js';

export function registerCitiesRoutes(
  app: FastifyInstance,
  deps: AppDependencies,
) {
  // GET /api/v1/cities — list all available cities
  app.get('/api/v1/cities', async (_request, _reply) => {
    return {
      cities: ALL_CITY_CONFIGS.map((c) => ({
        id: c.id,
        name: c.name,
        nameAr: c.nameAr,
        nameFr: c.nameFr,
        rolloutStatus: c.rolloutStatus,
        clusterRadiusMeters: c.clusterRadiusMeters,
        activeRoutingProvider: c.activeRoutingProvider,
      })),
    };
  });

  // GET /api/v1/cities/:id — get a specific city
  app.get<{ Params: { id: string } }>(
    '/api/v1/cities/:id',
    async (request, reply) => {
      const city = await deps.cityConfigRepository.findById(request.params.id);
      if (!city) {
        return reply.status(404).send({
          error: 'city_not_found',
          message: `City with id "${request.params.id}" not found`,
        });
      }
      return city;
    },
  );
}
