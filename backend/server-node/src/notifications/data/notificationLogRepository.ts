/**
 * `notification_log` — the record the cooldown and daily cap are computed
 * from, and the dedupe that stops one event notifying twice.
 */
import { getAdminClient } from "../../ingestion/supabaseAdmin";
import { unwrapRows } from "../../supabase";
import { getLogger } from "../../logger";
import { NotificationKind } from "../types";

const logger = getLogger("notifications.log");

export interface LogEntry {
  kind: NotificationKind;
  dedupeKey: string | null;
  sentAt: string;
}

/** Everything sent to [userId] in the last 24 hours — the window both policy
 * rules are expressed over, so there is never a reason to read more. */
export async function recentForUser(userId: string): Promise<LogEntry[]> {
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const rows = await unwrapRows<Record<string, unknown>>(
    getAdminClient()
      .from("notification_log")
      .select("kind, dedupe_key, sent_at")
      .eq("user_id", userId)
      .gte("sent_at", since)
      .order("sent_at", { ascending: false }),
  );
  return rows.map((row) => ({
    kind: row.kind as NotificationKind,
    dedupeKey: (row.dedupe_key as string | null) ?? null,
    sentAt: row.sent_at as string,
  }));
}

/**
 * Claims the right to send, and returns false if someone already has.
 *
 * This is a write, not a check, and the distinction is the point: the unique
 * index on `(user_id, kind, dedupe_key)` makes the insert itself the lock, so
 * two concurrent hook deliveries for the same finished job cannot both read
 * "not sent yet" and both send. A read-then-write dedupe has exactly that
 * race, and the 3D hook is fired by a database trigger that pg_net will retry.
 *
 * Returns true when this caller won the claim.
 */
export async function claim(
  userId: string,
  kind: NotificationKind,
  dedupeKey: string | null,
): Promise<boolean> {
  const { error } = await getAdminClient()
    .from("notification_log")
    .insert({ user_id: userId, kind, dedupe_key: dedupeKey });

  if (!error) return true;

  // 23505 = unique_violation: another delivery of the same event got here
  // first. Any other error means the log is unavailable, and refusing to
  // notify because bookkeeping is down would be the wrong failure — send.
  if ((error as { code?: string }).code === "23505") return false;

  logger.exception("notification_log insert failed; sending anyway", error);
  return true;
}
