import type { FastifyInstance } from 'fastify';
import type { AppDependencies } from '../composition-root.js';

const generateBodySchema = {
  type: 'object' as const,
  required: ['cityId', 'theme', 'timeBudgetMinutes'],
  properties: {
    cityId: { type: 'string', description: 'UUID of the target city' },
    theme: { type: 'string', description: 'Route theme (heritage, nature, culture, all)' },
    timeBudgetMinutes: {
      type: 'integer',
      minimum: 15,
      maximum: 1440,
      description: 'Time budget in minutes (15–1440)',
    },
  },
  additionalProperties: false,
};

interface GenerateBody {
  cityId: string;
  theme: string;
  timeBudgetMinutes: number;
}

export function registerRouteGenerationRoute(
  app: FastifyInstance,
  deps: AppDependencies,
) {
  app.post<{ Body: GenerateBody }>(
    '/api/v1/routes/generate',
    {
      schema: {
        body: generateBodySchema,
        response: {
          200: {
            type: 'object',
            properties: {
              cityId: { type: 'string' },
              theme: { type: 'string' },
              timeBudgetMinutes: { type: 'integer' },
              transportMode: { type: 'string' },
              segments: { type: 'array' },
              waypoints: { type: 'array' },
              estimatedTotalDurationMinutes: { type: 'integer' },
              dayCountFlag: { type: 'integer' },
              id: { type: 'string' },
              generatedAt: { type: 'string', format: 'date-time' },
              pipelineMs: { type: 'number' },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const { cityId, theme, timeBudgetMinutes } = request.body;

      const startTime = performance.now();

      const route = await deps.orchestrator.generate({
        cityId,
        theme,
        timeBudgetMinutes,
      });

      const elapsed = (performance.now() - startTime).toFixed(1);
      request.log.info(
        { cityId, theme, timeBudgetMinutes, elapsed: `${elapsed}ms`, waypoints: route.waypoints.length },
        'Route generated',
      );

      // Persist the route (in-memory for now).
      const persisted = await deps.routeRepository.save(route, {});

      return reply.status(200).send({
        id: persisted.id,
        ...route,
        generatedAt: persisted.generatedAt.toISOString(),
        pipelineMs: parseFloat(elapsed),
      });
    },
  );
}
