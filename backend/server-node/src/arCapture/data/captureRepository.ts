/**
 * Layer 5 — Capture Repository. Append-only capture attempts, accepted and
 * rejected — the anti-cheat audit trail (plan §3, §7).
 *
 * Supplies `captureValidator.CaptureHistory` — every field on that interface
 * is one of these methods, called once each by the orchestrator before it
 * invokes the pure validator (plan §5.7's checks 2, 3, 8, 9).
 *
 * `device_fix` is a GEOGRAPHY(POINT, 4326). On insert we use the same
 * insert_mascot_capture RPC pattern (PostGIS expression in column value).
 *
 * STATUS: implemented.
 */
import { getAdminClient } from "../../ingestion/supabaseAdmin";
import { unwrap, unwrapRows } from "../../supabase";
import type { Coordinate } from "../../routeGeneration/types";
import { MascotCapture } from "../types";

export interface CaptureRepository {
  /** Idempotency (check 2): a capture already recorded under this nonce. */
  findByNonce(nonce: string): Promise<MascotCapture | null>;
  /** Check 3: an `accepted` row already exists for this spawn. */
  hasAcceptedCapture(spawnId: string): Promise<boolean>;
  /** Check 8's baseline. */
  findLastAccepted(userId: string): Promise<{ fix: Coordinate; clientTs: string } | null>;
  /** Check 9. */
  countAcceptedSince(userId: string, since: Date): Promise<number>;
  insert(capture: Omit<MascotCapture, "id" | "createdAt">): Promise<MascotCapture>;
  /** Admin audit view (`GET /admin/captures?flagged=true`, plan §6). */
  findFlagged(): Promise<MascotCapture[]>;
}

const SELECT_WITH_GEO =
  "id, spawn_id, user_id, session_id, client_nonce, outcome, " +
  "ST_AsGeoJSON(device_fix)::jsonb as device_fix, " +
  "fix_accuracy_m, measured_distance_m, placement, ar_telemetry, " +
  "flags, client_ts, is_offline_replay, created_at";

function parsePointOrNull(raw: unknown): Coordinate | null {
  if (!raw) return null;
  try {
    const gj = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (gj && (gj as { coordinates?: unknown }).coordinates) {
      const [lng, lat] = (gj as { coordinates: [number, number] }).coordinates;
      return { lat, lng };
    }
  } catch {
    // fall through
  }
  return null;
}

function rowToCapture(row: Record<string, unknown>): MascotCapture {
  return {
    id: row.id as string,
    spawnId: row.spawn_id as string,
    userId: (row.user_id as string | null) ?? null,
    clientNonce: row.client_nonce as string,
    outcome: row.outcome as MascotCapture["outcome"],
    deviceFix: parsePointOrNull(row.device_fix),
    fixAccuracyM: row.fix_accuracy_m != null ? Number(row.fix_accuracy_m) : null,
    measuredDistanceM: row.measured_distance_m != null ? Number(row.measured_distance_m) : null,
    placement: (row.placement as MascotCapture["placement"]) ?? null,
    arTelemetry: (row.ar_telemetry as Record<string, unknown>) ?? {},
    flags: (row.flags as string[]) ?? [],
    clientTs: row.client_ts as string,
    isOfflineReplay: row.is_offline_replay as boolean,
    createdAt: row.created_at as string,
  };
}

class SupabaseCaptureRepository implements CaptureRepository {
  async findByNonce(nonce: string): Promise<MascotCapture | null> {
    const row = await unwrap<Record<string, unknown>>(
      getAdminClient()
        .from("mascot_captures")
        .select(SELECT_WITH_GEO)
        .eq("client_nonce", nonce)
        .single(),
    );
    return row ? rowToCapture(row) : null;
  }

  async hasAcceptedCapture(spawnId: string): Promise<boolean> {
    const row = await unwrap<{ count: string }>(
      getAdminClient()
        .from("mascot_captures")
        .select("count", { count: "exact", head: true })
        .eq("spawn_id", spawnId)
        .eq("outcome", "accepted"),
    );
    // head:true + count:exact returns { count } — supabase-js puts it on the response
    // but `unwrap` returns data, so we check the row itself or fall back to count query
    // Alternative: use select("id").limit(1) and check if null
    const check = await unwrap<Record<string, unknown>>(
      getAdminClient()
        .from("mascot_captures")
        .select("id")
        .eq("spawn_id", spawnId)
        .eq("outcome", "accepted")
        .limit(1)
        .single(),
    );
    return check !== null;
  }

  async findLastAccepted(userId: string): Promise<{ fix: Coordinate; clientTs: string } | null> {
    const row = await unwrap<Record<string, unknown>>(
      getAdminClient()
        .from("mascot_captures")
        .select("ST_AsGeoJSON(device_fix)::jsonb as device_fix, client_ts")
        .eq("user_id", userId)
        .eq("outcome", "accepted")
        .not("device_fix", "is", null)
        .order("created_at", { ascending: false })
        .limit(1)
        .single(),
    );
    if (!row) return null;
    const fix = parsePointOrNull(row.device_fix);
    if (!fix) return null;
    return { fix, clientTs: row.client_ts as string };
  }

  async countAcceptedSince(userId: string, since: Date): Promise<number> {
    const { count, error } = await getAdminClient()
      .from("mascot_captures")
      .select("*", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("outcome", "accepted")
      .gte("created_at", since.toISOString());
    if (error) throw error;
    return count ?? 0;
  }

  async insert(capture: Omit<MascotCapture, "id" | "createdAt">): Promise<MascotCapture> {
    const row = await unwrap<Record<string, unknown>>(
      getAdminClient().rpc("insert_mascot_capture", {
        p_spawn_id: capture.spawnId,
        p_user_id: capture.userId,
        p_client_nonce: capture.clientNonce,
        p_outcome: capture.outcome,
        p_fix_lng: capture.deviceFix?.lng ?? null,
        p_fix_lat: capture.deviceFix?.lat ?? null,
        p_fix_accuracy_m: capture.fixAccuracyM,
        p_measured_distance_m: capture.measuredDistanceM,
        p_placement: capture.placement,
        p_ar_telemetry: capture.arTelemetry,
        p_flags: capture.flags,
        p_client_ts: capture.clientTs,
        p_is_offline_replay: capture.isOfflineReplay,
      }),
    );
    if (!row) throw new Error("insert_mascot_capture returned no row");
    return rowToCapture(row as Record<string, unknown>);
  }

  async findFlagged(): Promise<MascotCapture[]> {
    const rows = await unwrapRows<Record<string, unknown>>(
      getAdminClient()
        .from("mascot_captures")
        .select(SELECT_WITH_GEO)
        .filter("array_length(flags, 1)", "gt", "0")
        .order("created_at", { ascending: false }),
    );
    return rows.map(rowToCapture);
  }
}

let shared: CaptureRepository | null = null;

export function getCaptureRepository(): CaptureRepository {
  if (shared === null) shared = new SupabaseCaptureRepository();
  return shared;
}
