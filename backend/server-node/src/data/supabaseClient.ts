/**
 * Cached Supabase client for read-only catalogue access.
 *
 * This module intentionally exposes nothing beyond a client getter — every
 * actual query lives in `locationsRepo.ts`, which is also where the
 * fallback-to-curated-data behaviour lives (see docs/backend/12: "the curated
 * 8 are the floor. Never show an empty map.").
 */
import { createClient, SupabaseClient } from "@supabase/supabase-js";

import { Config, ConfigurationError } from "../config";

let client: SupabaseClient | null = null;

export function isConfigured(): boolean {
  return Boolean(Config.SUPABASE_URL && Config.SUPABASE_ANON_KEY);
}

export function getClient(): SupabaseClient {
  if (!isConfigured()) {
    throw new ConfigurationError(
      "SUPABASE_URL / SUPABASE_ANON_KEY are not set. Add them to backend/.env.",
    );
  }
  if (client === null) {
    client = createClient(Config.SUPABASE_URL as string, Config.SUPABASE_ANON_KEY as string, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return client;
}

/**
 * A client that acts as the holder of `jwt`. supabase-py took this as
 * `ClientOptions(headers=...)`; supabase-js nests it under `global.headers`.
 *
 * Deliberately not cached — it carries a caller's credentials.
 */
export function getUserClient(jwt: string): SupabaseClient {
  return createClient(Config.SUPABASE_URL as string, Config.SUPABASE_ANON_KEY as string, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
