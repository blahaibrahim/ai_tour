/**
 * Layer 3 — Notification Policy. Pure function, no dependencies.
 *
 * Decides whether a server-originated push is allowed (plan §5.6). This is
 * deliberately narrow: proximity ("you're getting hot") alerts are fired by a
 * *client-side* OS geofence, never by this — FCM push exists only for
 * genuinely server-originated events, an admin publishing a new mascot on a
 * route in progress or a manifest invalidation. This function is what a
 * `Push Adapter` call is gated behind either way.
 *
 * STATUS: implemented for real — pure arithmetic over a log the caller
 * supplies, no Data or Adapter dependency.
 */
import { NotificationLogEntry, NotificationPrefs } from "../types";

/** Plan §5.6's cooldown table. */
export const NOTIFICATION_COOLDOWN_MS = 15 * 60 * 1000;
export const MAX_NOTIFICATIONS_PER_DAY = 6;

export interface ShouldNotifyInput {
  spawnId: string;
  /** This user's sent-notification log, most recent first or in any order —
   * only entries within the last 24h of `now` matter. */
  recent: NotificationLogEntry[];
  now: Date;
  prefs: NotificationPrefs;
}

/** True if `now`, interpreted as `prefs`' local hour, falls in the
 * 22:00–07:00 quiet window (wrapping past midnight). Hard-suppressed per
 * plan §5.6 — quiet hours are not merely a default. */
export function isQuietHours(now: Date, prefs: NotificationPrefs): boolean {
  const hour = now.getHours();
  const { quietHoursStart: start, quietHoursEnd: end } = prefs;
  if (start === end) return false; // a zero-width window means "never quiet"
  return start < end ? hour >= start && hour < end : hour >= start || hour < end;
}

export function shouldNotify(input: ShouldNotifyInput): boolean {
  const { spawnId, recent, now, prefs } = input;

  if (prefs.optedOut) return false;
  if (isQuietHours(now, prefs)) return false;

  const dayAgo = now.getTime() - 24 * 60 * 60 * 1000;
  const last24h = recent.filter((entry) => new Date(entry.sentAt).getTime() >= dayAgo);
  if (last24h.length >= MAX_NOTIFICATIONS_PER_DAY) return false;

  const lastForSpawn = last24h
    .filter((entry) => entry.spawnId === spawnId)
    .reduce<number>((latest, entry) => Math.max(latest, new Date(entry.sentAt).getTime()), 0);
  if (lastForSpawn !== 0 && now.getTime() - lastForSpawn < NOTIFICATION_COOLDOWN_MS) return false;

  return true;
}
