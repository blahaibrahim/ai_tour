/**
 * `notification_prefs` — one row per user, written by the "Notify me" button
 * and by the Settings toggles.
 */
import { getAdminClient } from "../../ingestion/supabaseAdmin";
import { unwrap } from "../../supabase";
import { defaultPrefs, NotificationPrefs } from "../types";

function rowToPrefs(row: Record<string, unknown>): NotificationPrefs {
  return {
    userId: row.user_id as string,
    enabled: row.enabled as boolean,
    quietHoursStart: Number(row.quiet_hours_start),
    quietHoursEnd: Number(row.quiet_hours_end),
    utcOffsetMinutes: Number(row.utc_offset_minutes ?? 0),
    routeReady: row.route_ready as boolean,
    modelReady: row.model_ready as boolean,
    mascotNearby: row.mascot_nearby as boolean,
  };
}

/** Never null: a user with no row gets [defaultPrefs], which is opted *out*.
 * Callers therefore never have to distinguish "no row" from "opted out" when
 * deciding whether to send — only the prefs endpoint does, so the client can
 * tell "never asked" from "answered no" and know whether to show the prompt. */
export async function getPrefs(userId: string): Promise<NotificationPrefs> {
  const row = await unwrap<Record<string, unknown>>(
    getAdminClient().from("notification_prefs").select("*").eq("user_id", userId).maybeSingle(),
  );
  return row ? rowToPrefs(row) : defaultPrefs(userId);
}

/** True when the user has answered the prompt at all, either way. */
export async function hasAnswered(userId: string): Promise<boolean> {
  const row = await unwrap<Record<string, unknown>>(
    getAdminClient().from("notification_prefs").select("user_id").eq("user_id", userId).maybeSingle(),
  );
  return row !== null;
}

export interface PrefsPatch {
  enabled?: boolean;
  quietHoursStart?: number;
  quietHoursEnd?: number;
  utcOffsetMinutes?: number;
  routeReady?: boolean;
  modelReady?: boolean;
  mascotNearby?: boolean;
}

/** Upsert. Absent fields keep whatever is already stored — the Settings screen
 * flips one switch at a time and must not silently reset the others. */
export async function upsertPrefs(
  userId: string,
  patch: PrefsPatch,
): Promise<NotificationPrefs> {
  const current = await getPrefs(userId);
  const merged = {
    user_id: userId,
    enabled: patch.enabled ?? current.enabled,
    quiet_hours_start: patch.quietHoursStart ?? current.quietHoursStart,
    quiet_hours_end: patch.quietHoursEnd ?? current.quietHoursEnd,
    utc_offset_minutes: patch.utcOffsetMinutes ?? current.utcOffsetMinutes,
    route_ready: patch.routeReady ?? current.routeReady,
    model_ready: patch.modelReady ?? current.modelReady,
    mascot_nearby: patch.mascotNearby ?? current.mascotNearby,
    updated_at: new Date().toISOString(),
  };

  const row = await unwrap<Record<string, unknown>>(
    getAdminClient()
      .from("notification_prefs")
      .upsert(merged, { onConflict: "user_id" })
      .select("*")
      .single(),
  );
  if (!row) throw new Error("notification_prefs upsert returned no row");
  return rowToPrefs(row);
}
