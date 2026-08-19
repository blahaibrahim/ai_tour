/**
 * `user_notifications` — the traveller's own copy of everything they were told.
 *
 * The counterpart to `notificationLogRepository`, and the difference between
 * them is worth being precise about: the log answers *may I send this?* and is
 * read back over a 24-hour window by the cooldown; the inbox answers *what have
 * I been told?* and is read by the app's notifications screen. The log holds no
 * copy and the traveller cannot see it; the inbox holds the sentences and the
 * traveller owns them — RLS lets them mark a row read, delete one, or empty the
 * lot (supabase/migrations/20260819120000).
 *
 * This module only writes. Reads and deletes go straight from the app to
 * PostgREST under those policies, because a server round trip would add nothing
 * to a query already scoped to `auth.uid()` — the same reasoning as
 * `lib/repositories/saved_locations_repository.dart`.
 */
import { getAdminClient } from "../../ingestion/supabaseAdmin";
import { getLogger } from "../../logger";
import { NotificationKind, PushPayload } from "../types";

const logger = getLogger("notifications.inbox");

/**
 * Files one notification in [userId]'s inbox.
 *
 * Never throws. Filing is bookkeeping around an event that has already
 * happened, and a failed insert must not stop the push that is the whole
 * reason this was called — so a failure is logged and reported, not raised.
 *
 * Returns false when nothing was filed, which covers two different cases the
 * caller does not need to tell apart: a duplicate `dedupe_key` (the unique
 * index rejected it, meaning this event is already in the inbox) and the table
 * being unavailable.
 */
export async function file(
  userId: string,
  kind: NotificationKind,
  payload: PushPayload,
  dedupeKey: string | null = null,
): Promise<boolean> {
  const { error } = await getAdminClient().from("user_notifications").insert({
    user_id: userId,
    kind,
    title: payload.title,
    body: payload.body,
    // The same map FCM carries, so the app's deep-link switch reads one shape
    // whether the tap came from the tray or from the notifications screen.
    data: payload.data ?? {},
    dedupe_key: dedupeKey,
  });

  if (!error) return true;

  // 23505 = unique_violation. Expected, not a fault: pg_net retries the
  // model-job hook, and the studio's notify button is a button a human can
  // press twice.
  if ((error as { code?: string }).code === "23505") return false;

  logger.exception(`Could not file a ${kind} notification for ${userId}`, error);
  return false;
}
