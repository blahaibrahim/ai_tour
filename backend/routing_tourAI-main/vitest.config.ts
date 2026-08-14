import { defineConfig } from 'vitest/config';
import { loadEnv } from 'vite';

export default defineConfig({
  test: {
    /**
     * Load environment variables from .env so integration tests
     * (e.g. graphhopper.adapter.integration.test.ts) can read
     * ROUTING_PROVIDER_GRAPHHOPPER_API_KEY without having to pass
     * it inline on the command line.
     */
    env: loadEnv('', process.cwd(), ''),
    testTimeout: 15000,
  },
});
