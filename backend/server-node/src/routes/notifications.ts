/**
 * Layer 1 — notification endpoints.
 *
 *   POST   /api/devices/push-token        register/refresh this device's FCM token
 *   DELETE /api/devices/push-token        drop it (sign-out, or the toggle going off)
 *   GET    /api/notifications/prefs       what "Notify me" is currently set to
 *   PUT    /api/notifications/prefs       set it
 *   POST   /api/internal/model-job-notify the model_jobs trigger's webhook
 *   POST   /api/internal/splat-notify      the studio dashboard's notify button
 *
 * `POST /api/devices/push-token` used to live in `routes/mascots.ts` and go
 * through `arCapture`'s fixture switch, which meant it wrote nothing whenever
 * `AR_CAPTURE_MODE` was unset. It is served here now, on the same path and
 * with the same contract, against the real repository — see
 * `src/notifications/index.ts`'s header for why.
 */
import { Router } from "express";
import type { Response } from "express";

import { Config } from "../config";
import { getPushTokenRepository } from "../arCapture/data/pushTokenRepository";
import type { DevicePlatform } from "../arCapture/types";
import { getAdminClient } from "../ingestion/supabaseAdmin";
import { getLogger } from "../logger";
import * as notifications from "../notifications";
import { authenticateAndRateLimit } from "../rateLimit";
import { asyncHandler } from "./asyncHandler";

const logger = getLogger("routes.notifications");

export const notificationsRouter = Router();

const PLATFORMS = new Set<DevicePlatform>(["android", "ios", "web"]);

function serverError(res: Response, error: unknown, what: string): Response {
  logger.exception(`Unhandled error in ${what}`, error);
  return res.status(500).json({ error: "server_error" });
}

function serializePrefs(prefs: notifications.NotificationPrefs, answered: boolean) {
  return {
    enabled: prefs.enabled,
    // Lets the client tell "never asked" from "answered no" — the thinking
    // screen keeps offering "Notify me" only in the first case.
    answered,
    quiet_hours_start: prefs.quietHoursStart,
    quiet_hours_end: prefs.quietHoursEnd,
    utc_offset_minutes: prefs.utcOffsetMinutes,
    route_ready: prefs.routeReady,
    model_ready: prefs.modelReady,
    mascot_nearby: prefs.mascotNearby,
    splat_ready: prefs.splatReady,
    // So the app can say "notifications aren't set up on this server" rather
    // than claiming a push that will never arrive.
    push_configured: notifications.isPushConfigured(),
  };
}

// --- device tokens ---------------------------------------------------------

notificationsRouter.post(
  "/api/devices/push-token",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "register_push_token", 30, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const body = (req.body ?? {}) as Record<string, unknown>;
    if (typeof body.token !== "string" || !body.token) {
      return res.status(400).json({ error: "bad_request", message: "token is required" });
    }
    if (typeof body.platform !== "string" || !PLATFORMS.has(body.platform as DevicePlatform)) {
      return res.status(400).json({
        error: "bad_request",
        message: `platform must be one of ${[...PLATFORMS].join(", ")}`,
      });
    }

    try {
      await getPushTokenRepository().upsert({
        userId: auth.user.id,
        token: body.token,
        platform: body.platform as DevicePlatform,
        arCapability: typeof body.ar_capability === "string" ? body.ar_capability : null,
      });

      // Registering a token is the one moment the server is guaranteed to
      // hear from the device, so it is where the offset quiet hours are
      // evaluated against gets refreshed — including after the traveller
      // crosses a timezone mid-trip.
      const offset = Number(body.utc_offset_minutes);
      if (Number.isFinite(offset) && Math.abs(offset) <= 14 * 60) {
        await notifications.upsertPrefs(auth.user.id, { utcOffsetMinutes: offset });
      }

      return res.status(204).send();
    } catch (error) {
      return serverError(res, error, "POST /api/devices/push-token");
    }
  }),
);

/** Sign-out, or the notifications toggle going off.
 *
 * Deleting the token rather than only flipping `enabled` matters: an opted-out
 * user with a live token still receives anything a future bug forgets to gate,
 * and a signed-out device holding a token would keep receiving the previous
 * account's notifications until FCM rotated it. */
notificationsRouter.delete(
  "/api/devices/push-token",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "delete_push_token", 30, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const body = (req.body ?? {}) as Record<string, unknown>;
    const token = typeof body.token === "string" ? body.token : null;

    try {
      const query = getAdminClient().from("push_tokens").delete().eq("user_id", auth.user.id);
      // Scoped to the one device when a token is given, so signing out of a
      // phone does not silence the same account's tablet.
      const { error } = await (token ? query.eq("token", token) : query);
      if (error) throw error;
      return res.status(204).send();
    } catch (error) {
      return serverError(res, error, "DELETE /api/devices/push-token");
    }
  }),
);

// --- preferences -----------------------------------------------------------

notificationsRouter.get(
  "/api/notifications/prefs",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "get_notification_prefs", 120, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    try {
      const [prefs, answered] = await Promise.all([
        notifications.getPrefs(auth.user.id),
        notifications.hasAnswered(auth.user.id),
      ]);
      return res.json(serializePrefs(prefs, answered));
    } catch (error) {
      return serverError(res, error, "GET /api/notifications/prefs");
    }
  }),
);

/** Partial update: only the fields present are changed. This is what the
 * "Notify me" button calls with `{enabled: true}`, and what each Settings
 * switch calls with its own one field. */
notificationsRouter.put(
  "/api/notifications/prefs",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "set_notification_prefs", 60, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const body = (req.body ?? {}) as Record<string, unknown>;
    const patch: Record<string, unknown> = {};

    const bools: [string, string][] = [
      ["enabled", "enabled"],
      ["route_ready", "routeReady"],
      ["model_ready", "modelReady"],
      ["mascot_nearby", "mascotNearby"],
      ["splat_ready", "splatReady"],
    ];
    for (const [wire, field] of bools) {
      if (wire in body) {
        if (typeof body[wire] !== "boolean") {
          return res.status(400).json({ error: "bad_request", message: `${wire} must be a boolean` });
        }
        patch[field] = body[wire];
      }
    }

    const hours: [string, string][] = [
      ["quiet_hours_start", "quietHoursStart"],
      ["quiet_hours_end", "quietHoursEnd"],
    ];
    for (const [wire, field] of hours) {
      if (wire in body) {
        const value = Number(body[wire]);
        if (!Number.isInteger(value) || value < 0 || value > 23) {
          return res
            .status(400)
            .json({ error: "bad_request", message: `${wire} must be an integer hour 0-23` });
        }
        patch[field] = value;
      }
    }

    if ("utc_offset_minutes" in body) {
      const value = Number(body.utc_offset_minutes);
      if (!Number.isFinite(value) || Math.abs(value) > 14 * 60) {
        return res
          .status(400)
          .json({ error: "bad_request", message: "utc_offset_minutes is out of range" });
      }
      patch.utcOffsetMinutes = value;
    }

    try {
      const prefs = await notifications.upsertPrefs(auth.user.id, patch);
      return res.json(serializePrefs(prefs, true));
    } catch (error) {
      return serverError(res, error, "PUT /api/notifications/prefs");
    }
  }),
);

// --- internal webhook ------------------------------------------------------

/**
 * Called by the `trg_model_jobs_notify` trigger through pg_net whenever a
 * `model_jobs` row reaches a terminal status
 * (`supabase/migrations/20260811120000_notifications.sql`).
 *
 * Not authenticated as a user — there is no user session behind a database
 * trigger. It is authenticated as *the database*, by a shared secret held in
 * `private.app_settings`, and it answers 204 to anything it decides not to
 * send so pg_net does not retry a deliberate suppression.
 */
notificationsRouter.post(
  "/api/internal/model-job-notify",
  asyncHandler(async (req, res) => {
    const expected = Config.NOTIFY_HOOK_SECRET;
    if (!expected) {
      logger.warning("model-job-notify called but NOTIFY_HOOK_SECRET is not set; ignoring.");
      return res.status(503).json({ error: "not_configured" });
    }
    if (req.header("X-Notify-Secret") !== expected) {
      logger.warning("model-job-notify called with a bad secret.");
      return res.status(401).json({ error: "unauthorized" });
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    const userId = typeof body.user_id === "string" ? body.user_id : null;
    const jobId = typeof body.job_id === "string" ? body.job_id : null;
    const status = typeof body.status === "string" ? body.status : null;
    if (!userId || !jobId || !status) {
      return res
        .status(400)
        .json({ error: "bad_request", message: "user_id, job_id and status are required" });
    }
    if (status !== "succeeded" && status !== "failed" && status !== "cancelled") {
      return res.status(204).send();
    }

    const result = await notifications.sendToUser(
      userId,
      notifications.modelJobPayload({
        status,
        jobId,
        artifactId: typeof body.artifact_id === "string" ? body.artifact_id : null,
        errorCode: typeof body.error_code === "string" ? body.error_code : null,
      }),
      {
        kind: "model_ready",
        dedupeKey: jobId,
        // The traveller took a photo and was told to come back later. Being
        // over the daily cap is not a reason to leave them waiting on a job
        // that has already finished.
        bypassRateLimits: true,
      },
    );

    return res.status(204).setHeader("X-Delivered", String(result.delivered)).send();
  }),
);

// --- the studio's notify button --------------------------------------------

/**
 * Tells a traveller that footage they recorded has been turned into a gaussian
 * splat.
 *
 * Called by `website/gaussian_splatting` — a local-only operator dashboard, not
 * a user-facing site — when whoever is running the pipeline decides a finished
 * scene is worth showing off. Authenticated the same way the model-job hook is:
 * by a shared secret, because the caller is an operator tool rather than a
 * session. It deliberately does *not* accept `title`/`body`; the copy lives in
 * `notifications.splatReadyPayload` so every splat notification reads the same
 * however many dashboards learn to send one.
 *
 * The contributor is named by email rather than by id because that is what the
 * dashboard's operator actually knows — the studio shows clips and scenes, and
 * nothing in `videos/assignments.json` carries a `user_id`. Resolving it here
 * keeps the service_role user lookup on this side of the wire.
 */
notificationsRouter.post(
  "/api/internal/splat-notify",
  asyncHandler(async (req, res) => {
    const expected = Config.NOTIFY_HOOK_SECRET;
    if (!expected) {
      logger.warning("splat-notify called but NOTIFY_HOOK_SECRET is not set; ignoring.");
      return res.status(503).json({ error: "not_configured" });
    }
    if (req.header("X-Notify-Secret") !== expected) {
      logger.warning("splat-notify called with a bad secret.");
      return res.status(401).json({ error: "unauthorized" });
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    const str = (key: string) => (typeof body[key] === "string" ? (body[key] as string).trim() : "");

    const email = str("email").toLowerCase();
    const scene = str("scene");
    const splatPath = str("splat_path");
    const sceneTitle = str("scene_title") || scene;
    if (!email || !scene || !splatPath) {
      return res.status(400).json({
        error: "bad_request",
        message: "email, scene and splat_path are required",
      });
    }
    // The bucket is fixed by the migration; accepting an arbitrary path would
    // let a compromised secret point the app's viewer at any object the signer
    // can reach.
    if (!splatPath.startsWith("splats/")) {
      return res.status(400).json({
        error: "bad_request",
        message: "splat_path must be a key in the splats bucket",
      });
    }

    let userId: string;
    try {
      const found = await findUserIdByEmail(email);
      if (!found) return res.status(404).json({ error: "no_such_user", email });
      userId = found;
    } catch (error) {
      return serverError(res, error, "POST /api/internal/splat-notify");
    }

    const result = await notifications.sendToUser(
      userId,
      notifications.splatReadyPayload({
        sceneTitle,
        splatPath,
        scene,
        gaussians: Number(body.gaussians) || 0,
        poiId: typeof body.poi_id === "string" ? body.poi_id : null,
      }),
      {
        kind: "splat_ready",
        // The scene, so re-pressing the button after a better-quality re-train
        // does not file a second copy of the same news. Deleting the row in the
        // app is how a traveller gets rid of it, not a second send.
        dedupeKey: splatPath,
        // A splat arrives days after the capture and there is exactly one of
        // them per scene. "You have had six notifications today" is not a
        // reason to drop the seventh when the seventh is this.
        bypassRateLimits: true,
      },
    );

    return res.json({
      user_id: userId,
      delivered: result.delivered,
      suppressed_reason: result.suppressedReason ?? null,
    });
  }),
);

/**
 * An email address -> the auth user id, or null.
 *
 * GoTrue's admin API has no "get user by email", and the `auth` schema is not
 * exposed through PostgREST, so this pages through `listUsers` and matches
 * locally. Bounded at ten pages: this is an operator tool naming a traveller it
 * already knows, and an unbounded scan of a large project on every press would
 * be a worse failure than "not found".
 */
async function findUserIdByEmail(email: string): Promise<string | null> {
  const admin = getAdminClient();
  const perPage = 200;
  for (let page = 1; page <= 10; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw error;
    const users = data?.users ?? [];
    const match = users.find((user) => (user.email ?? "").toLowerCase() === email);
    if (match) return match.id;
    if (users.length < perPage) return null;
  }
  return null;
}
