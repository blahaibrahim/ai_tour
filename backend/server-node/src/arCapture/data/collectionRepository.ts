/**
 * Layer 5 — Collection Repository. User ↔ mascot album (plan §3, §7).
 *
 * `mascot_collection` has UNIQUE (user_id, mascot_id) so upsert is safe —
 * on conflict we increment `capture_count` and leave `first_captured_at`
 * untouched. We do this via a dedicated RPC to avoid a read-modify-write
 * race condition.
 *
 * STATUS: implemented.
 */
import { getAdminClient } from "../../ingestion/supabaseAdmin";
import { unwrap, unwrapRows } from "../../supabase";
import { CollectionEntry } from "../types";

export interface CollectionRepository {
  findByUserAndMascot(userId: string, mascotId: string): Promise<CollectionEntry | null>;
  findAllForUser(userId: string): Promise<CollectionEntry[]>;
  upsert(entry: CollectionEntry): Promise<CollectionEntry>;
}

function rowToEntry(row: Record<string, unknown>): CollectionEntry {
  return {
    id: row.id as string,
    userId: row.user_id as string,
    mascotId: row.mascot_id as string,
    firstCapturedAt: row.first_captured_at as string,
    captureCount: row.capture_count as number,
  };
}

class SupabaseCollectionRepository implements CollectionRepository {
  async findByUserAndMascot(userId: string, mascotId: string): Promise<CollectionEntry | null> {
    const row = await unwrap<Record<string, unknown>>(
      getAdminClient()
        .from("mascot_collection")
        .select("*")
        .eq("user_id", userId)
        .eq("mascot_id", mascotId)
        .single(),
    );
    return row ? rowToEntry(row) : null;
  }

  async findAllForUser(userId: string): Promise<CollectionEntry[]> {
    const rows = await unwrapRows<Record<string, unknown>>(
      getAdminClient()
        .from("mascot_collection")
        .select("*")
        .eq("user_id", userId)
        .order("first_captured_at", { ascending: false }),
    );
    return rows.map(rowToEntry);
  }

  async upsert(entry: CollectionEntry): Promise<CollectionEntry> {
    // ON CONFLICT (user_id, mascot_id) DO UPDATE SET capture_count = capture_count + 1
    const row = await unwrap<Record<string, unknown>>(
      getAdminClient().rpc("upsert_mascot_collection", {
        p_user_id: entry.userId,
        p_mascot_id: entry.mascotId,
        p_capture_count: entry.captureCount,
        p_first_captured_at: entry.firstCapturedAt,
      }),
    );
    if (!row) throw new Error("upsert_mascot_collection returned no row");
    return rowToEntry(row as Record<string, unknown>);
  }
}

let shared: CollectionRepository | null = null;

export function getCollectionRepository(): CollectionRepository {
  if (shared === null) shared = new SupabaseCollectionRepository();
  return shared;
}
