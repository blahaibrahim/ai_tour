/**
 * The notifications module's public face — `sendToUser` and the copy that
 * goes with each event.
 *
 * **Why this is not part of `arCapture`.** The push token repository and the
 * cooldown policy were both written inside that module (docs/mascot_plan.md
 * §7), but `arCapture/index.ts` switches its whole Data layer on
 * `AR_CAPTURE_MODE`, which defaults to `fixture` — so `upsertPushToken` there
 * returns an invented row and never writes. That is correct for a mascot
 * manifest and wrong for a device token: a traveller who presses "Notify me"
 * on a deployment running AR fixtures would be told notifications are on while
 * their token was silently discarded. Push tokens are infrastructure for three
 * separate features, only one of which is the hunt, so they live here and are
 * always real. `arCapture`'s own `FcmPushAdapter` now delegates to this file.
 *
 * **What this module does not send.** One of the app's three notification
 * triggers is deliberately client-side and never reaches here: *a fennec is
 * near*. docs/mascot_plan.md §5.6 rules push out for proximity — it needs
 * connectivity and would require streaming the traveller's live position to
 * the backend. It is an OS-local notification driven by the client's own band
 * tracker, and everything needed to decide it is already on the device.
 *
 * The other two are sent from here. `model_ready` is the obvious one: it
 * happens minutes later on a GPU with the app very possibly closed.
 * `route_ready` is less obvious, because the client holds the generating
 * request open and normally learns the answer first — but a request whose app
 * has been killed still runs to completion on this side, and a push is then
 * the only thing that can reach the traveller. That is exactly the case the
 * "Notify me" button is for, so the push goes out unconditionally and the
 * client suppresses its own local copy whenever push is deliverable.
 */
import { getLogger } from "../logger";
import { MAX_NOTIFICATIONS_PER_DAY, NOTIFICATION_COOLDOWN_MS } from "../arCapture/domain/notificationPolicy";
import { getPushTokenRepository } from "../arCapture/data/pushTokenRepository";
import { isPushConfigured, sendPush } from "./adapters/fcmAdapter";
import * as inbox from "./data/inboxRepository";
import { claim, recentForUser } from "./data/notificationLogRepository";
import { getPrefs } from "./data/notificationPrefsRepository";
import { NotificationKind, NotificationPrefs, PushPayload, SendResult } from "./types";

const logger = getLogger("notifications");

export * from "./types";
export { getPrefs, hasAnswered, upsertPrefs } from "./data/notificationPrefsRepository";
export { file as fileInbox } from "./data/inboxRepository";
export { isPushConfigured, sendPush } from "./adapters/fcmAdapter";

/**
 * True if `now` falls inside the user's quiet window, evaluated in *their*
 * local time via `prefs.utcOffsetMinutes`.
 *
 * `arCapture/domain/notificationPolicy.isQuietHours` does the same arithmetic
 * against `now.getHours()` — the server's own timezone — which is right only
 * when the server and the traveller share one. This deployment's server does
 * not necessarily sit in Algeria, so the offset the device reported wins.
 */
export function isQuietHours(now: Date, prefs: NotificationPrefs): boolean {
  const { quietHoursStart: start, quietHoursEnd: end } = prefs;
  if (start === end) return false; // zero-width window means "never quiet"

  const localMinutes = now.getUTCHours() * 60 + now.getUTCMinutes() + prefs.utcOffsetMinutes;
  // Modulo twice: a negative offset before midnight UTC lands the first result
  // below zero, which would compare as an hour in the small hours.
  const hour = Math.floor((((localMinutes % 1440) + 1440) % 1440) / 60);

  return start < end ? hour >= start && hour < end : hour >= start || hour < end;
}

/** Whether [kind] is switched on in [prefs]. */
function kindEnabled(prefs: NotificationPrefs, kind: NotificationKind): boolean {
  switch (kind) {
    case "route_ready":
      return prefs.routeReady;
    case "model_ready":
      return prefs.modelReady;
    case "mascot_nearby":
      return prefs.mascotNearby;
    case "splat_ready":
      return prefs.splatReady;
  }
}

export interface SendOptions {
  kind: NotificationKind;
  /** The subject of the notification — a job id, a spawn id. Two sends with
   * the same key notify once, ever. Null opts out of dedupe entirely. */
  dedupeKey?: string | null;
  /** Skip the cooldown and daily cap. For events the traveller explicitly
   * asked to be told about exactly once, where "you have had six already
   * today" is not a reason to stay silent about the seventh. */
  bypassRateLimits?: boolean;
}

/**
 * Applies the policy, then sends. Never throws — a caller has already
 * completed the work this is merely announcing.
 */
export async function sendToUser(
  userId: string,
  payload: PushPayload,
  options: SendOptions,
): Promise<SendResult> {
  try {
    const prefs = await getPrefs(userId);

    // The inbox is filed before any of the push gates below, and the split
    // between what suppresses which is the whole design:
    //
    //   * **Quiet hours, the cooldown, the daily cap and a missing token**
    //     suppress the *push* only. Every one of them answers "should this
    //     interrupt them right now"; a row in a list they chose to open
    //     interrupts nobody, and a 3 a.m. model that vanished because it was
    //     3 a.m. is exactly the notification worth keeping.
    //   * **The per-kind opt-out** suppresses both. That switch is the
    //     traveller saying they do not care about this class of event, which is
    //     as true of the list as of the tray.
    //   * **`enabled: false` suppresses the push only**, because it is also
    //     what "never asked" looks like (see `defaultPrefs`). Reading it as
    //     "keep no history" would leave the notifications screen permanently
    //     empty for everyone who has not yet pressed "Notify me" — including
    //     the traveller who is about to be told their footage became a splat.
    if (!kindEnabled(prefs, options.kind)) {
      return { delivered: 0, suppressedReason: "kind_disabled" };
    }

    const dedupeKey = options.dedupeKey ?? null;
    await inbox.file(userId, options.kind, payload, dedupeKey);

    if (!isPushConfigured()) return { delivered: 0, suppressedReason: "no_tokens" };
    if (!prefs.enabled) return { delivered: 0, suppressedReason: "opted_out" };
    if (isQuietHours(new Date(), prefs)) {
      return { delivered: 0, suppressedReason: "quiet_hours" };
    }

    if (!options.bypassRateLimits) {
      const recent = await recentForUser(userId);
      if (recent.length >= MAX_NOTIFICATIONS_PER_DAY) {
        logger.info(`Daily notification cap reached for ${userId}; suppressing ${options.kind}.`);
        return { delivered: 0, suppressedReason: "duplicate" };
      }
      const lastOfKind = recent
        .filter((entry) => entry.kind === options.kind)
        .reduce((latest, entry) => Math.max(latest, Date.parse(entry.sentAt)), 0);
      if (lastOfKind !== 0 && Date.now() - lastOfKind < NOTIFICATION_COOLDOWN_MS) {
        return { delivered: 0, suppressedReason: "duplicate" };
      }
    }

    // Claim before sending, not after. FCM has no rollback, so the only way a
    // duplicate can be prevented rather than merely noticed is to lose the
    // race before the message goes out.
    if (!(await claim(userId, options.kind, dedupeKey))) {
      logger.info(`Already notified ${userId} about ${options.kind}:${dedupeKey}; skipping.`);
      return { delivered: 0, suppressedReason: "duplicate" };
    }

    const tokens = (await getPushTokenRepository().findByUser(userId)).map((t) => t.token);
    if (tokens.length === 0) return { delivered: 0, suppressedReason: "no_tokens" };

    const delivered = await sendPush(tokens, payload);
    logger.info(`Sent ${options.kind} to ${delivered}/${tokens.length} device(s) for ${userId}.`);
    return { delivered };
  } catch (error) {
    logger.exception("sendToUser failed (non-fatal)", error);
    return { delivered: 0 };
  }
}

// ---------------------------------------------------------------------------
// Event copy
// ---------------------------------------------------------------------------

/**
 * The "your route is ready" notification.
 *
 * `route_id` in the data block is what makes the notification worth tapping.
 * If the app was killed while generating — the case this push exists for —
 * nothing about the route survives in the client's memory, so the id is the
 * only way back to it. The client re-fetches through `GET /api/routes/:id`,
 * which works because a generated route is persisted before this is sent.
 */
export function routeReadyPayload(input: {
  routeId: string;
  stopCount: number;
  theme: string;
}): PushPayload {
  return {
    title: "Your route is ready",
    body: input.stopCount == 1
      ? "One stop is waiting for you. Tap to see it."
      : `${input.stopCount} stops are waiting for you. Tap to see them.`,
    data: {
      type: "route_ready",
      route_id: input.routeId,
      theme: input.theme,
    },
  };
}

/**
 * The "your 3D model is ready / didn't work out" notification.
 *
 * Failure copy is specific per docs/backend/06's "Failure is specific" note —
 * `no_subject` is the common case and is the traveller's to fix, so saying
 * what to do differently is worth more than the word "failed".
 */
export function modelJobPayload(input: {
  status: string;
  artifactId: string | null;
  jobId: string;
  errorCode: string | null;
}): PushPayload {
  const data: Record<string, string> = {
    type: "model_ready",
    job_id: input.jobId,
    status: input.status,
  };
  if (input.artifactId) data.artifact_id = input.artifactId;
  if (input.errorCode) data.error_code = input.errorCode;

  if (input.status === "succeeded") {
    return {
      title: "Your 3D model is ready",
      body: "Tap to see it in your folder.",
      data,
    };
  }

  return {
    title: "That capture didn't work out",
    body: modelFailureBody(input.errorCode),
    data,
  };
}

/**
 * The "your footage became a 3D scene" notification.
 *
 * Sent from the studio dashboard, by hand, when a gaussian splat trained from a
 * traveller's clip is worth showing them — see
 * `website/gaussian_splatting/components/Studio.tsx`. Unlike the other three
 * this is not a status update on something they are waiting for; it lands days
 * later, unprompted, about footage they have probably forgotten recording. So
 * the copy leads with the place, which is the part they will recognise.
 *
 * `splat_path` is what makes the tap worth making. The app's splat viewer takes
 * a `splats/<scene>/<file>` storage key, signs it and streams the decimated
 * point cloud — without it the notification would be a compliment with nowhere
 * to go.
 */
export function splatReadyPayload(input: {
  sceneTitle: string;
  splatPath: string;
  scene: string;
  gaussians: number;
  poiId: string | null;
}): PushPayload {
  const data: Record<string, string> = {
    type: "splat_ready",
    splat_path: input.splatPath,
    scene: input.scene,
    scene_title: input.sceneTitle,
    gaussians: String(input.gaussians),
  };
  if (input.poiId) data.poi_id = input.poiId;

  return {
    title: `${input.sceneTitle} is now in 3D`,
    body: "Your footage helped build it. Tap to walk around the scene.",
    data,
  };
}

function modelFailureBody(errorCode: string | null): string {
  switch (errorCode) {
    case "no_subject":
      return "We couldn't find a clear object — try filling more of the frame with it.";
    case "timeout":
      return "It took too long to build. Tap to try that photo again.";
    case "quota_exceeded":
      return "You've used all your model credits for today.";
    default:
      return "Something went wrong building it. Tap to try again.";
  }
}
