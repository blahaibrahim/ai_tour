/**
 * Shapes for the notifications module.
 *
 * `PushPayload` is deliberately identical to the one in
 * `arCapture/adapters/pushAdapter.ts` — that interface was specified first
 * (docs/mascot_plan.md §7) and its `FcmPushAdapter` now delegates here rather
 * than keeping a second, divergent definition of "what a push looks like".
 */

/** What a notification is *about*. Doubles as the `notification_log.kind`
 * value and as the per-category opt-out column name on `notification_prefs`,
 * so the three never drift apart. */
export type NotificationKind =
  | "route_ready"
  | "model_ready"
  | "mascot_nearby"
  /** Footage this traveller recorded became a gaussian splat. Sent from the
   * studio dashboard, days after the capture, and the only one of the four
   * whose subject is a thing to go and look at rather than a status. */
  | "splat_ready";

export interface PushPayload {
  title: string;
  body: string;
  /** Delivered to the client as `RemoteMessage.data`. Values must be strings —
   * FCM rejects anything else. `NotificationService._handleData` on the Flutter
   * side reads `type` to decide where a tap should land. */
  data?: Record<string, string>;
}

export interface NotificationPrefs {
  userId: string;
  enabled: boolean;
  /** Local hours, 0-23. `start === end` means "never quiet". */
  quietHoursStart: number;
  quietHoursEnd: number;
  /** The device's offset from UTC in minutes, so quiet hours are evaluated in
   * the traveller's local time rather than the server's. */
  utcOffsetMinutes: number;
  routeReady: boolean;
  modelReady: boolean;
  mascotNearby: boolean;
  splatReady: boolean;
}

/** The prefs a user who has never answered the "Notify me" prompt has.
 *
 * `enabled: false` is the important half. A missing row means "never asked",
 * and sending to someone who never opted in — even though they cannot have a
 * push token registered, so nothing would actually go out — would make the
 * absence of a row mean something different in the policy than it does in the
 * UI, which is exactly the kind of mismatch that produces a notification
 * nobody can explain. */
export function defaultPrefs(userId: string): NotificationPrefs {
  return {
    userId,
    enabled: false,
    quietHoursStart: 22,
    quietHoursEnd: 7,
    utcOffsetMinutes: 0,
    routeReady: true,
    modelReady: true,
    mascotNearby: true,
    splatReady: true,
  };
}

export interface SendResult {
  /** How many device tokens accepted the message. 0 is a normal outcome — the
   * user may be opted out, capped, or simply have no device registered. */
  delivered: number;
  /** Why nothing was sent, when `delivered` is 0 and it was a decision rather
   * than a delivery failure. */
  suppressedReason?: "opted_out" | "kind_disabled" | "quiet_hours" | "duplicate" | "no_tokens";
}
