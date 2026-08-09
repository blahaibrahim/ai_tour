/**
 * Layer 5 — Push Token Repository. Device push tokens, platform, last-seen
 * (plan §3, §7). Server-originated events only — never the proximity-alert
 * mechanism, which is client-side geofencing (plan §5.6).
 *
 * STATUS: implemented.
 */
import { getAdminClient } from "../../ingestion/supabaseAdmin";
import { unwrap, unwrapRows } from "../../supabase";
import { DevicePlatform, PushToken } from "../types";

export interface PushTokenRepository {
  findByUser(userId: string): Promise<PushToken[]>;
  upsert(input: {
    userId: string;
    token: string;
    platform: DevicePlatform;
    arCapability: string | null;
  }): Promise<PushToken>;
}

function rowToToken(row: Record<string, unknown>): PushToken {
  return {
    id: row.id as string,
    userId: row.user_id as string,
    token: row.token as string,
    platform: row.platform as DevicePlatform,
    arCapability: (row.ar_capability as string | null) ?? null,
    lastSeenAt: row.last_seen_at as string,
  };
}

class SupabasePushTokenRepository implements PushTokenRepository {
  async findByUser(userId: string): Promise<PushToken[]> {
    const rows = await unwrapRows<Record<string, unknown>>(
      getAdminClient()
        .from("push_tokens")
        .select("*")
        .eq("user_id", userId),
    );
    return rows.map(rowToToken);
  }

  async upsert(input: {
    userId: string;
    token: string;
    platform: DevicePlatform;
    arCapability: string | null;
  }): Promise<PushToken> {
    const now = new Date().toISOString();
    const row = await unwrap<Record<string, unknown>>(
      getAdminClient()
        .from("push_tokens")
        .upsert(
          {
            user_id: input.userId,
            token: input.token,
            platform: input.platform,
            ar_capability: input.arCapability,
            last_seen_at: now,
          },
          { onConflict: "token" },
        )
        .select("*")
        .single(),
    );
    if (!row) throw new Error("push_token upsert returned no row");
    return rowToToken(row);
  }
}

let shared: PushTokenRepository | null = null;

export function getPushTokenRepository(): PushTokenRepository {
  if (shared === null) shared = new SupabasePushTokenRepository();
  return shared;
}
