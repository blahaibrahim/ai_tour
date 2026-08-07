/**
 * The one place in this codebase that holds the Supabase service_role key.
 *
 * Kept entirely separate from `data/supabaseClient.ts` (anon key, used by
 * every read path). Everything this client touches is still mediated by
 * narrow RPCs (`find_location_match`, `upsert_ingested_location`,
 * `upsert_poi_tile`) rather than raw table writes — see docs/backend/12 and
 * docs/backend/07's "the app/server never holds more privilege than the
 * specific thing it needs to do" principle, applied here to the ingestion
 * pipeline instead of the 3D endpoint.
 */
import { createClient, SupabaseClient } from "@supabase/supabase-js";

import { Config, requireServiceRoleKey } from "../config";

let adminClient: SupabaseClient | null = null;

export function getAdminClient(): SupabaseClient {
  if (adminClient === null) {
    adminClient = createClient(Config.SUPABASE_URL as string, requireServiceRoleKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return adminClient;
}
