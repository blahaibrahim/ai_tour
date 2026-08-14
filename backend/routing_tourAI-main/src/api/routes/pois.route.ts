import type { FastifyInstance } from 'fastify';
import type { AppDependencies } from '../composition-root.js';
import { THEME_CATEGORY_MAP } from '../../data/fixtures/index.js';

export function registerPoisRoute(
  app: FastifyInstance,
  deps: AppDependencies,
) {
  // GET /api/v1/cities/:cityId/pois — list published POIs for a city
  app.get<{
    Params: { cityId: string };
    Querystring: { theme?: string };
  }>(
    '/api/v1/cities/:cityId/pois',
    async (request, reply) => {
      const { cityId } = request.params;
      const { theme } = request.query;

      // Verify city exists.
      const city = await deps.cityConfigRepository.findById(cityId);
      if (!city) {
        return reply.status(404).send({
          error: 'city_not_found',
          message: `City with id "${cityId}" not found`,
        });
      }

      // Build category filter from theme if provided.
      let categoryIds: string[] | undefined;
      if (theme) {
        categoryIds = THEME_CATEGORY_MAP[theme];
        if (!categoryIds) {
          return reply.status(400).send({
            error: 'invalid_theme',
            message: `Unknown theme "${theme}". Available: ${Object.keys(THEME_CATEGORY_MAP).join(', ')}`,
          });
        }
      }

      const pois = await deps.poiRepository.findEligible({
        cityId,
        ...(categoryIds && categoryIds.length > 0 ? { categoryIds } : {}),
      });

      return {
        city: { id: city.id, name: city.name },
        theme: theme ?? 'all',
        count: pois.length,
        pois: pois.map((p) => ({
          id: p.id,
          nameFr: p.nameFr,
          nameAr: p.nameAr,
          nameEn: p.nameEn,
          location: p.location,
          avgVisitDurationMinutes: p.avgVisitDurationMinutes,
          checkpointRadiusMeters: p.checkpointRadiusMeters,
        })),
      };
    },
  );
}
