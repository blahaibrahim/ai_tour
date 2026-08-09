/**
 * Layer 1 — AR Capture Controller (docs/mascot_plan.md §3, §6).
 *
 * Same shape as `routes/routes.ts`: authenticate + rate-limit, validate into
 * a typed request, hand to the module, let `sendError` map the outcome. No
 * distance math, no domain knowledge here — that all lives in
 * `src/arCapture`.
 *
 * Deviations from plan §6's HTTP surface, both documented in
 * `src/arCapture/README.md`'s deviations table:
 *   - `/api/...` paths, not `/v1/...` — this deployment's existing convention
 *     (every other router in `routes/` uses `/api`).
 *   - `Idempotency-Key` is the request body's `nonce` field rather than a
 *     separate header — Flow C's own JSON shape (plan §4) already carries a
 *     `nonce`, so a second, header-based idempotency key would just be two
 *     names for the same value.
 *   - The admin endpoints (`/admin/pois/:poiId/ar-content`,
 *     `/admin/ar-contents/:id/spawn-zone`, `/admin/captures?flagged=true`)
 *     are not built — there is no admin auth surface anywhere in this
 *     deployment yet, AR or otherwise.
 */
import { Router } from "express";
import type { Response } from "express";

import { getLogger } from "../logger";
import { authenticateAndRateLimit } from "../rateLimit";
import * as arCapture from "../arCapture";
import { ArCaptureError } from "../arCapture/errors";
import { asyncHandler } from "./asyncHandler";

const logger = getLogger("routes.mascots");

export const mascotsRouter = Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PLATFORMS = new Set(["android", "ios", "web"]);

function sendError(res: Response, error: unknown): Response {
  if (error instanceof ArCaptureError) {
    if (error.code === "not_implemented") {
      logger.warning(`not implemented: ${error.message}`);
    }
    return res.status(error.status).json({ error: error.code, message: error.message });
  }
  logger.exception("Unhandled AR capture error", error);
  return res.status(500).json({ error: "server_error" });
}

interface ValidationFailure {
  error: string;
  message: string;
}

function isFailure<T>(value: T | ValidationFailure): value is ValidationFailure {
  return typeof value === "object" && value !== null && "error" in value;
}

function isCoordinate(value: unknown): value is { lat: number; lng: number } {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as Record<string, unknown>).lat === "number" &&
    typeof (value as Record<string, unknown>).lng === "number"
  );
}

// --- serialization -----------------------------------------------------

function serializeManifest(manifest: arCapture.SpawnManifest): Record<string, unknown> {
  return {
    route_id: manifest.routeId,
    spawns: manifest.spawns.map((s) => ({
      spawn_id: s.spawnId,
      poi_id: s.poiId,
      lat: s.location.lat,
      lng: s.location.lng,
      capture_radius_meters: s.captureRadiusMeters,
      hot_radius_meters: s.hotRadiusMeters,
      band_thresholds: {
        cold_meters: s.bandThresholds.coldMeters,
        warm_meters: s.bandThresholds.warmMeters,
        hot_meters: s.bandThresholds.hotMeters,
        burning_meters: s.bandThresholds.burningMeters,
      },
      presentation_distance_meters: s.presentationDistanceMeters,
      mascot: {
        id: s.mascot.id,
        key: s.mascot.key,
        name: s.mascot.name,
        rarity: s.mascot.rarity,
        model_glb_url: s.mascot.modelGlbUrl,
        model_usdz_url: s.mascot.modelUsdzUrl,
        model_checksum: s.mascot.modelChecksum,
        scale_meters: s.mascot.scaleMeters,
      },
    })),
  };
}

function serializeCaptureResult(result: arCapture.CaptureResponse): Record<string, unknown> {
  return {
    outcome: result.outcome,
    reward: result.reward,
    is_first_catch: result.isFirstCatch,
    collection: result.collection
      ? { mascot_id: result.collection.mascotId, capture_count: result.collection.captureCount }
      : null,
  };
}

function serializeCollectionEntry(entry: arCapture.CollectionEntry): Record<string, unknown> {
  return {
    mascot_id: entry.mascotId,
    first_captured_at: entry.firstCapturedAt,
    capture_count: entry.captureCount,
  };
}

// --- endpoints -----------------------------------------------------------

/** Flow A (plan §4): assembles (and, in `real` mode, persists) the spawn
 * manifest for every AR-enabled stop on the route. Idempotent per route/POI
 * pair — the schema's `UNIQUE (route_id, poi_id)` makes a repeat call safe. */
mascotsRouter.post(
  "/api/routes/:routeId/mascots/generate",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "generate_mascots", 60, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const routeId = req.params.routeId;
    if (!UUID_RE.test(routeId)) {
      return res.status(400).json({ error: "bad_request", message: "routeId must be a uuid" });
    }

    try {
      const manifest = await arCapture.generateManifest(routeId);
      return res.status(201).json(serializeManifest(manifest));
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

mascotsRouter.get(
  "/api/routes/:routeId/mascots",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "get_mascots", 300, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const routeId = req.params.routeId;
    if (!UUID_RE.test(routeId)) {
      return res.status(400).json({ error: "bad_request", message: "routeId must be a uuid" });
    }

    try {
      const manifest = await arCapture.getManifest(routeId);
      return res.json(serializeManifest(manifest));
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

/** Flow C step 2 (plan §5.7): the first verified proximity claim, gating a
 * signed capture token. */
mascotsRouter.post(
  "/api/mascots/:spawnId/proximity",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "mascot_proximity", 120, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const spawnId = req.params.spawnId;
    if (!UUID_RE.test(spawnId)) {
      return res.status(400).json({ error: "bad_request", message: "spawnId must be a uuid" });
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    if (!isCoordinate(body.fix)) {
      return res.status(400).json({ error: "bad_request", message: "fix must be {lat, lng}" });
    }
    const accuracyMeters = Number(body.accuracy_meters);
    if (!Number.isFinite(accuracyMeters) || accuracyMeters < 0) {
      return res
        .status(400)
        .json({ error: "bad_request", message: "accuracy_meters must be a non-negative number" });
    }

    try {
      const token = await arCapture.issueProximityToken(
        spawnId,
        auth.user.id,
        body.fix,
        accuracyMeters,
      );
      return res.json({ capture_token: token.token, expires_at: token.expiresAt });
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

function parseCaptureRequest(
  spawnId: string,
  userId: string,
  body: Record<string, unknown>,
): arCapture.CaptureRequest | ValidationFailure {
  if (typeof body.capture_token !== "string" || !body.capture_token) {
    return { error: "bad_request", message: "capture_token is required" };
  }
  if (!isCoordinate(body.fix)) {
    return { error: "bad_request", message: "fix must be {lat, lng}" };
  }
  const accuracyMeters = Number(body.accuracy_meters);
  if (!Number.isFinite(accuracyMeters) || accuracyMeters < 0) {
    return { error: "bad_request", message: "accuracy_meters must be a non-negative number" };
  }
  if (typeof body.client_ts !== "string" || Number.isNaN(Date.parse(body.client_ts))) {
    return { error: "bad_request", message: "client_ts must be an ISO 8601 timestamp" };
  }
  if (typeof body.nonce !== "string" || !body.nonce) {
    return { error: "bad_request", message: "nonce is required (idempotency key)" };
  }

  return {
    spawnId,
    userId,
    captureToken: body.capture_token,
    fix: body.fix,
    accuracyMeters,
    clientTs: body.client_ts,
    clientNonce: body.nonce,
    arTelemetry:
      typeof body.ar_telemetry === "object" && body.ar_telemetry !== null
        ? (body.ar_telemetry as Record<string, unknown>)
        : {},
    isOfflineReplay: body.is_offline_replay === true,
  };
}

/** Flow C steps 7-9 (plan §4, §5.7). `nonce` in the body is the idempotency
 * key — see this file's header note. */
mascotsRouter.post(
  "/api/mascots/:spawnId/capture",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "mascot_capture", 60, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const spawnId = req.params.spawnId;
    if (!UUID_RE.test(spawnId)) {
      return res.status(400).json({ error: "bad_request", message: "spawnId must be a uuid" });
    }

    const parsed = parseCaptureRequest(spawnId, auth.user.id, (req.body ?? {}) as Record<string, unknown>);
    if (isFailure(parsed)) return res.status(400).json(parsed);

    try {
      const result = await arCapture.submitCapture(parsed);
      return res.json(serializeCaptureResult(result));
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

/** Offline outbox replay (plan §4, §10): each queued capture replays with
 * its original fix and timestamp. One capture's failure does not abort the
 * batch — the client needs every result to know what to drop from its queue
 * and what to retry. */
mascotsRouter.post(
  "/api/mascots/captures/batch",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "mascot_capture_batch", 30, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const body = (req.body ?? {}) as Record<string, unknown>;
    if (!Array.isArray(body.captures)) {
      return res.status(400).json({ error: "bad_request", message: "captures must be an array" });
    }
    if (body.captures.length > 50) {
      return res.status(400).json({ error: "bad_request", message: "at most 50 captures per batch" });
    }

    const results: unknown[] = [];
    for (const raw of body.captures) {
      const item = (raw ?? {}) as Record<string, unknown>;
      const spawnId = typeof item.spawn_id === "string" ? item.spawn_id : "";
      if (!UUID_RE.test(spawnId)) {
        results.push({ error: "bad_request", message: "spawn_id must be a uuid" });
        continue;
      }
      const parsed = parseCaptureRequest(spawnId, auth.user.id, {
        ...item,
        is_offline_replay: true,
      });
      if (isFailure(parsed)) {
        results.push(parsed);
        continue;
      }
      try {
        results.push(serializeCaptureResult(await arCapture.submitCapture(parsed)));
      } catch (error) {
        if (error instanceof ArCaptureError) {
          results.push({ error: error.code, message: error.message });
        } else {
          logger.exception("Unhandled error in capture batch item", error);
          results.push({ error: "server_error" });
        }
      }
    }
    return res.json({ results });
  }),
);

/** `GET /v1/mascots/:mascotId/asset` in the plan (§6). Redirects to a
 * time-limited signed URL rather than proxying the model bytes — the file is
 * served as a static asset behind the storage layer's own caching. */
mascotsRouter.get(
  "/api/mascots/:mascotId/asset",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "get_mascot_asset", 120, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const mascotId = req.params.mascotId;
    if (!UUID_RE.test(mascotId)) {
      return res.status(400).json({ error: "bad_request", message: "mascotId must be a uuid" });
    }

    try {
      const asset = await arCapture.getMascotAsset(mascotId);
      const wantsUsdz = req.query.format === "usdz";
      res.setHeader("X-Asset-Checksum", asset.checksum);
      return res.redirect(302, wantsUsdz ? asset.usdzUrl : asset.glbUrl);
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

mascotsRouter.get(
  "/api/collection",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "get_collection", 300, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    try {
      const entries = await arCapture.getCollection(auth.user.id);
      return res.json({ collection: entries.map(serializeCollectionEntry) });
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

mascotsRouter.post(
  "/api/devices/push-token",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "register_push_token", 30, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const body = (req.body ?? {}) as Record<string, unknown>;
    if (typeof body.token !== "string" || !body.token) {
      return res.status(400).json({ error: "bad_request", message: "token is required" });
    }
    if (typeof body.platform !== "string" || !PLATFORMS.has(body.platform)) {
      return res
        .status(400)
        .json({ error: "bad_request", message: `platform must be one of ${[...PLATFORMS].join(", ")}` });
    }

    try {
      await arCapture.upsertPushToken({
        userId: auth.user.id,
        token: body.token,
        platform: body.platform as arCapture.DevicePlatform,
        arCapability: typeof body.ar_capability === "string" ? body.ar_capability : null,
      });
      return res.status(204).send();
    } catch (error) {
      return sendError(res, error);
    }
  }),
);
