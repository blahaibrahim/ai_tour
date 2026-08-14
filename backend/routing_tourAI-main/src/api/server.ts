import { createApp } from './composition-root.js';
import { loadEnv } from '../config/env.js';

/**
 * Server entry point. Creates the Fastify app with all dependencies
 * wired, then starts listening.
 *
 * Usage:
 *   npm run dev:api    (watch mode via tsx)
 *   npm run start      (production, runs compiled JS)
 */
async function main() {
  const env = loadEnv();
  const { app } = await createApp();

  try {
    await app.listen({ port: env.PORT, host: env.HOST });
    app.log.info(
      'Route Generation API ready — %d cities, listening on %s:%d',
      3,
      env.HOST,
      env.PORT,
    );
  } catch (err) {
    app.log.fatal(err, 'Failed to start server');
    process.exit(1);
  }

  // Graceful shutdown on SIGINT / SIGTERM.
  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.on(signal, async () => {
      app.log.info('Received %s, shutting down', signal);
      await app.close();
      process.exit(0);
    });
  }
}

main();
