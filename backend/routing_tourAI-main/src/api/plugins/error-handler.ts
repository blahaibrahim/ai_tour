import type { FastifyInstance } from 'fastify';
import { RoutingProviderError } from '../../adapters/routing-provider/errors.js';

/**
 * Global error handler that translates known error types into
 * structured JSON responses with appropriate HTTP status codes
 * (Section 3: "Validates requests, rate-limits, translates errors").
 */
export function registerErrorHandler(app: FastifyInstance) {
  app.setErrorHandler((err: unknown, _request, reply) => {
    const error = err as any;

    // Fastify validation errors (bad request body / params).
    if (error.validation) {
      return reply.status(400).send({
        error: 'validation_error',
        message: 'Invalid request',
        details: error.validation,
      });
    }

    // Rate limit exceeded.
    if (error.statusCode === 429) {
      return reply.status(429).send({
        error: 'rate_limit_exceeded',
        message: 'Too many requests. Please try again later.',
      });
    }

    // Domain errors (city not found, no POIs, etc.).
    if (error.message.includes('City config not found')) {
      return reply.status(404).send({
        error: 'city_not_found',
        message: error.message,
      });
    }

    if (error.message.includes('No eligible POIs found')) {
      return reply.status(404).send({
        error: 'no_pois_found',
        message: error.message,
      });
    }

    // Routing provider errors.
    if (error instanceof RoutingProviderError) {
      app.log.error({ err: error, provider: error.provider, code: error.code },
        'Routing provider error');
      return reply.status(502).send({
        error: 'routing_provider_error',
        message: `Routing provider (${error.provider}) failed: ${error.code}`,
      });
    }

    // Unexpected errors.
    app.log.error({ err: error }, 'Unhandled error');
    return reply.status(500).send({
      error: 'internal_error',
      message: 'An unexpected error occurred.',
    });
  });
}
