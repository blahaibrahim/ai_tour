import { config } from 'dotenv';
import { z } from 'zod';

config(); // Load .env file

const envSchema = z.object({
  DATABASE_URL: z.string().url().default('postgresql://localhost:5432/route_gen'),
  REDIS_URL: z.string().url().default('redis://localhost:6379'),
  ROUTING_PROVIDER_GRAPHHOPPER_API_KEY: z.string().trim().optional().transform(v => v === '' ? undefined : v),
  ROUTING_PROVIDER_ORS_API_KEY: z.string().trim().optional().transform(v => v === '' ? undefined : v),
  ROUTING_PROVIDER_TIMEOUT_MS: z.coerce.number().int().positive().default(3000),
  PORT: z.coerce.number().int().positive().default(3000),
  HOST: z.string().default('0.0.0.0'),
});

export type Env = z.infer<typeof envSchema>;

let cached: Env | undefined;

/**
 * Validates and returns process.env against envSchema. Throws with a
 * readable message on first access if required vars are missing — fail
 * fast at startup rather than deep inside an Adapter call. Only the
 * composition root (driver script, Step 6) calls this; individual
 * Adapter classes take their config as constructor params instead, so
 * they stay testable without touching process.env at all.
 */
export function loadEnv(): Env {
  if (!cached) {
    const parsed = envSchema.safeParse(process.env);
    if (!parsed.success) {
      throw new Error(`Invalid environment configuration: ${parsed.error.message}`);
    }
    cached = parsed.data;
  }
  return cached;
}
