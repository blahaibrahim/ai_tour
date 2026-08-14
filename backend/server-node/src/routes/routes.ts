/**
 * Layer 1 — Route Request Controller.
 *
 * Validates requests, rate-limits, translates errors (spec §3). Nothing else:
 * no sequencing, no domain knowledge, no provider awareness. The spec defers
 * this layer (§1, §9 step 6) and substitutes a driver script; it is built here
 * so the Flutter client has a real contract to develop against, and it is
 * deliberately thin enough that the deferred design has nothing to undo.
 *
 * Every handler is the same three steps: authenticate + rate-limit, validate
 * into a typed request, hand to the module and let `sendError` map the
 * outcome. Business rules — which cities are routable, which POIs are
 * eligible — live below this layer, not here.
 */
import { Router } from "express";
import type { Response } from "express";

import { getLogger } from "../logger";
import * as notifications from "../notifications";
import { authenticateAndRateLimit } from "../rateLimit";
import * as routeGeneration from "../routeGeneration";
import { RouteGenerationError } from "../routeGeneration/errors";
import { Locale, RouteRequest, TransportMode } from "../routeGeneration/types";
import { asyncHandler } from "./asyncHandler";

const logger = getLogger("routes.routeGeneration");

export const routesRouter = Router();

const TRANSPORT_MODES = new Set<TransportMode>(["walking", "driving", "hybrid"]);
const LOCALES = new Set<Locale>(["en", "fr", "ar"]);

/** 30 minutes is below any single stop's dwell time plus travel; 3 days is
 * past the point where the day-count flag is the honest answer instead. */
const MIN_TIME_BUDGET_MINUTES = 30;
const MAX_TIME_BUDGET_MINUTES = 3 * 24 * 60;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Translates a module error into its status code and body.
 *
 * Each `RouteGenerationError` subclass carries its own status, so this stays a
 * pass-through rather than a growing switch — adding an error type does not
 * mean editing the controller.
 */
function sendError(res: Response, error: unknown): Response {
  if (error instanceof RouteGenerationError) {
    if (error.code === "not_implemented") {
      logger.warning(`not implemented: ${error.message}`);
    }
    return res.status(error.status).json({ error: error.code, message: error.message });
  }
  logger.exception("Unhandled route-generation error", error);
  return res.status(500).json({ error: "server_error" });
}

interface ValidationFailure {
  error: string;
  message: string;
}

/** Parses and bounds-checks a generation request. Returns the request or the
 * 400 body to answer with — never both. */
function parseRouteRequest(
  body: Record<string, unknown>,
  userId: string,
): RouteRequest | ValidationFailure {
  const cityId = body.city_id;
  if (typeof cityId !== "string" || !UUID_RE.test(cityId)) {
    return { error: "bad_request", message: "city_id must be a uuid" };
  }

  const theme = typeof body.theme === "string" ? body.theme.trim() : "";
  if (!theme || theme.length > 60) {
    return { error: "bad_request", message: "theme is required" };
  }

  const timeBudget = Number(body.time_budget_minutes);
  if (!Number.isFinite(timeBudget) || !Number.isInteger(timeBudget)) {
    return { error: "bad_request", message: "time_budget_minutes must be a whole number" };
  }
  if (timeBudget < MIN_TIME_BUDGET_MINUTES || timeBudget > MAX_TIME_BUDGET_MINUTES) {
    return {
      error: "bad_request",
      message: `time_budget_minutes must be between ${MIN_TIME_BUDGET_MINUTES} and ${MAX_TIME_BUDGET_MINUTES}`,
    };
  }

  const transportMode = (body.transport_mode ?? "hybrid") as TransportMode;
  if (!TRANSPORT_MODES.has(transportMode)) {
    return {
      error: "bad_request",
      message: `transport_mode must be one of ${[...TRANSPORT_MODES].join(", ")}`,
    };
  }

  let categoryKeys: string[] | undefined;
  if (body.category_keys !== undefined) {
    if (!Array.isArray(body.category_keys)) {
      return { error: "bad_request", message: "category_keys must be an array of strings" };
    }
    categoryKeys = body.category_keys.filter((k): k is string => typeof k === "string").slice(0, 20);
  }

  const locale = (body.locale ?? "en") as Locale;
  if (!LOCALES.has(locale)) {
    return { error: "bad_request", message: `locale must be one of ${[...LOCALES].join(", ")}` };
  }

  return {
    cityId,
    theme,
    timeBudgetMinutes: timeBudget,
    transportMode,
    categoryKeys,
    locale,
    userId,
    sessionId: typeof body.session_id === "string" ? body.session_id : null,
  };
}

function isFailure(value: RouteRequest | ValidationFailure): value is ValidationFailure {
  return "error" in value;
}

// --- serialization ----------------------------------------------------------
// snake_case on the wire, camelCase inside the module. Done here rather than
// by naming the internal types in snake_case, so the domain layer reads as
// TypeScript and only the boundary knows about JSON conventions.

function serializeCity(city: routeGeneration.CityConfig): Record<string, unknown> {
  return {
    id: city.id,
    name: city.name,
    name_fr: city.nameFr,
    name_ar: city.nameAr,
    centre: city.centre,
    rollout_status: city.rolloutStatus,
    // `cluster_radius_meters` and `active_routing_provider` are deliberately
    // not exposed: they are server-side tuning, and the client has no use for
    // them that isn't a leak of how routing is done.
  };
}

function serializeStop(s: routeGeneration.RouteStop): Record<string, unknown> {
  return {
    poi_id: s.poiId,
    sequence_order: s.sequenceOrder,
    cluster_id: s.clusterId,
    name: s.name,
    description: s.description,
    category_key: s.categoryKey,
    lat: s.location.lat,
    lng: s.location.lng,
    dwell_minutes: s.dwellMinutes,
    checkpoint_radius_meters: s.checkpointRadiusMeters,
    opening_hours_raw: s.openingHoursRaw,
    photo_url: s.photoUrl,
    photo_attribution: s.photoAttribution,
    photo_license: s.photoLicense,
    photo_source_url: s.photoSourceUrl,
    ar_content_id: s.arContentId,
    stamp_id: s.stampId,
  };
}

function serializeRoute(route: routeGeneration.RouteResponse): Record<string, unknown> {
  return {
    id: route.id,
    city_id: route.cityId,
    theme: route.theme,
    time_budget_minutes: route.timeBudgetMinutes,
    transport_mode: route.transportMode,
    estimated_total_duration_minutes: route.estimatedTotalDurationMinutes,
    day_count_flag: route.dayCountFlag,
    generated_at: route.generatedAt,
    stops: route.stops.map(serializeStop),
    // Replacement candidates for the review step — see RouteResponse.alternates.
    // Same shape as a stop, so the client renders one with the same card, but
    // they carry sequence_order -1 and are not part of the route.
    alternates: route.alternates.map(serializeStop),
    segments: route.segments.map((seg) => ({
      mode: seg.mode,
      from_poi_id: seg.fromPoiId,
      to_poi_id: seg.toPoiId,
      cluster_id: seg.clusterId,
      duration_minutes: seg.durationMinutes,
      distance_meters: seg.distanceMeters,
      geometry: seg.geometry.map((c) => [c.lat, c.lng]),
    })),
  };
}

// --- endpoints --------------------------------------------------------------

/** Cities and their rollout status. Drives the city picker; a `planning` city
 * is listed but cannot be routed, which is the phased rollout made visible. */
routesRouter.get(
  "/api/cities",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "list_cities", 300, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    try {
      const cities = await routeGeneration.listCities();
      return res.json({ cities: cities.map(serializeCity) });
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

/** Themes and categories for the request builder. Returned together because
 * the picker needs both and they change at the same rate.
 *
 * `?city_id=` is optional and narrows the theme list to what that city can
 * actually answer — a theme whose categories hold no published POI there is
 * not offered, rather than offered and then refused with a 422. Omitting it
 * gives the union across every city, which is the right answer before the
 * traveller has picked one. */
routesRouter.get(
  "/api/categories",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "list_categories", 300, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const cityId = typeof req.query.city_id === "string" ? req.query.city_id : undefined;
    if (cityId !== undefined && !UUID_RE.test(cityId)) {
      return res.status(400).json({ error: "bad_request", message: "city_id must be a uuid" });
    }

    try {
      const [categories, themes] = await Promise.all([
        routeGeneration.listCategories(),
        routeGeneration.listThemes(cityId),
      ]);
      return res.json({
        categories: categories.map((c) => ({
          key: c.key,
          label_en: c.labelEn,
          label_fr: c.labelFr,
          label_ar: c.labelAr,
          icon_ref: c.iconRef,
          color_hex: c.colorHex,
        })),
        themes: themes.map((t) => ({
          key: t.key,
          label_en: t.labelEn,
          label_fr: t.labelFr,
          label_ar: t.labelAr,
        })),
      });
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

/**
 * Generate a route.
 *
 * Synchronous, unlike the job-and-poll endpoint it replaces: the spec's
 * latency budget is under 800 ms on a cache hit and 1.5 s cold (§4), which is
 * inside what a request can hold open. If that budget is ever missed in
 * practice, the answer is the cache, not a job queue.
 */
routesRouter.post(
  "/api/routes",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "generate_route", 60, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const parsed = parseRouteRequest((req.body ?? {}) as Record<string, unknown>, auth.user.id);
    if (isFailure(parsed)) return res.status(400).json(parsed);

    // Did this request's client survive long enough to be told the answer?
    //
    // This is the whole basis of the route-ready notification, so it is worth
    // being precise about. Three situations, and only the last one is this
    // server's to handle:
    //
    //   app in foreground  → nothing should be shown; the screen is about to
    //                        show the route itself.
    //   app backgrounded   → a notification should be shown, and the client
    //                        does it: it gets this response, and it is the
    //                        only party that knows its own lifecycle state.
    //   app killed         → a notification should be shown, and *only* a push
    //                        can do it — there is no process left to fire a
    //                        local one.
    //
    // The first two are indistinguishable from here and identical from here:
    // in both, the client receives the response and decides for itself. So the
    // server's rule is simply "push if, and only if, the answer could not be
    // delivered". Node keeps running this handler after its client
    // disconnects, which is what makes the third case reachable at all.
    let clientVanished = false;
    req.on("close", () => {
      // `close` also fires on ordinary completion, hence the guard: only a
      // close that beats the response means the client is gone.
      if (!res.writableEnded) clientVanished = true;
    });

    try {
      const route = await routeGeneration.generateRoute(parsed);
      res.json(serializeRoute(route));

      if (clientVanished) {
        // Never awaited — nothing is waiting on this, and `sendToUser`
        // swallows its own failures. It also applies the opt-in check, so a
        // traveller who never pressed "Notify me" gets nothing.
        void notifications.sendToUser(
          auth.user.id,
          notifications.routeReadyPayload({
            routeId: route.id,
            stopCount: route.stops.length,
            theme: route.theme,
          }),
          {
            kind: "route_ready",
            dedupeKey: route.id,
            // A traveller generating three routes in a row is waiting on each
            // one. The 15-minute per-kind cooldown would tell them about the
            // first and silently drop the other two.
            bypassRateLimits: true,
          },
        );
      }
      return res;
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

routesRouter.get(
  "/api/routes/:routeId",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "get_route", 600, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const routeId = req.params.routeId;
    if (!UUID_RE.test(routeId)) {
      return res.status(400).json({ error: "bad_request", message: "routeId must be a uuid" });
    }

    // Names and descriptions are stored per locale and resolved on read, so a
    // route generated in one language can be read back in another rather than
    // being frozen into whatever was asked for at generation time.
    const locale = (req.query.locale ?? "en") as Locale;
    if (!LOCALES.has(locale)) {
      return res.status(400).json({ error: "bad_request", message: "unsupported locale" });
    }

    try {
      const route = await routeGeneration.getRoute(routeId, auth.user.id, locale);
      return res.json(serializeRoute(route));
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

/**
 * NOT IN SPEC.
 *
 * Re-generates a route with some stops dropped, for the app's review step. The
 * design spec has no partial-route or refinement concept — routes are
 * immutable once generated — so this contract is provisional and needs
 * confirming with the module owner. It is modelled as "generate again,
 * excluding these" rather than as an edit, so the immutability rule holds.
 */
routesRouter.post(
  "/api/routes/:routeId/refine",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "refine_route", 120, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const routeId = req.params.routeId;
    if (!UUID_RE.test(routeId)) {
      return res.status(400).json({ error: "bad_request", message: "routeId must be a uuid" });
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    if (!Array.isArray(body.drop_poi_ids)) {
      return res
        .status(400)
        .json({ error: "bad_request", message: "drop_poi_ids must be an array of poi ids" });
    }
    const dropPoiIds = body.drop_poi_ids.filter((id): id is string => typeof id === "string");

    const parsed = parseRouteRequest(body, auth.user.id);
    if (isFailure(parsed)) return res.status(400).json(parsed);

    try {
      const route = await routeGeneration.refineRoute(routeId, dropPoiIds, parsed);
      return res.json(serializeRoute(route));
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

// --- progress ---------------------------------------------------------------
// Mutable state, kept behind its own endpoints because it is kept in its own
// tables — the route definition never changes as the traveller walks it.

routesRouter.post(
  "/api/routes/:routeId/progress",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "start_progress", 120, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const routeId = req.params.routeId;
    if (!UUID_RE.test(routeId)) {
      return res.status(400).json({ error: "bad_request", message: "routeId must be a uuid" });
    }

    try {
      const progress = await routeGeneration.startProgress(routeId);
      return res.json({
        id: progress.id,
        route_id: progress.routeId,
        status: progress.status,
        started_at: progress.startedAt,
        visited_poi_ids: progress.visitedPoiIds,
      });
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

routesRouter.get(
  "/api/progress/:progressId",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "get_progress", 600, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const progressId = req.params.progressId;
    if (!UUID_RE.test(progressId)) {
      return res.status(400).json({ error: "bad_request", message: "progressId must be a uuid" });
    }

    try {
      const progress = await routeGeneration.getProgress(progressId);
      if (!progress) return res.status(404).json({ error: "progress_not_found" });
      return res.json({
        id: progress.id,
        route_id: progress.routeId,
        status: progress.status,
        started_at: progress.startedAt,
        last_updated_at: progress.lastUpdatedAt,
        completed_at: progress.completedAt,
        visited_poi_ids: progress.visitedPoiIds,
      });
    } catch (error) {
      return sendError(res, error);
    }
  }),
);

/**
 * Records an arrival at a stop.
 *
 * Deliberately dumb: whether the traveller was actually inside the POI's
 * `checkpoint_radius_meters`, and how long they had to stay to confirm it, is
 * decided by the separate AR trigger service (spec §10). This endpoint logs
 * the event that service reports.
 */
routesRouter.post(
  "/api/progress/:progressId/checkpoint",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "record_checkpoint", 600, "1 hour");
    if (auth.failure) return res.status(auth.failure.status).json(auth.failure.body);

    const progressId = req.params.progressId;
    if (!UUID_RE.test(progressId)) {
      return res.status(400).json({ error: "bad_request", message: "progressId must be a uuid" });
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    const poiId = body.poi_id;
    if (typeof poiId !== "string" || !UUID_RE.test(poiId)) {
      return res.status(400).json({ error: "bad_request", message: "poi_id must be a uuid" });
    }

    try {
      const event = await routeGeneration.recordCheckpoint(progressId, poiId);
      return res.json({
        progress_id: event.progressId,
        poi_id: event.poiId,
        arrived_at: event.arrivedAt,
      });
    } catch (error) {
      return sendError(res, error);
    }
  }),
);
