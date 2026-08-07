/**
 * Manual trigger for POI ingestion (docs/backend/12).
 *
 * Deliberately its own endpoint, not a step inside `/api/itinerary`. A cold
 * tile means several sequential Overpass/Wikidata/Wikipedia/Commons round
 * trips per POI, with a deliberate delay between each (see ingestion/ingest.ts
 * — added after empirically hitting Overpass's rate limit while testing this).
 * That can run to tens of seconds per tile; blocking a user's itinerary
 * request on it would be a bad trade for a one-time cost that should be paid
 * once per area, not once per request. A background job or scheduled
 * pre-warm (docs/backend/12's "Pre-warming" section) is the production
 * answer — this endpoint is the synchronous, explicitly-triggered version of
 * the same operation, useful for backfilling an area on demand right now.
 *
 * Requires SUPABASE_SERVICE_ROLE_KEY (see config.requireServiceRoleKey) —
 * every other route in this app works without it.
 */
import { Router } from "express";

import { ConfigurationError } from "../config";
import { getUserClient } from "../data/supabaseClient";
import { ensureTilesIngested } from "../ingestion/ingest";
import { getAdminClient } from "../ingestion/supabaseAdmin";
import { getLogger } from "../logger";
import { bearerToken } from "../rateLimit";
import { unwrap } from "../supabase";
import { asyncHandler } from "./asyncHandler";

const logger = getLogger("routes.poi");

export const poiRouter = Router();

const MAX_RADIUS_KM = 50; // tighter than itinerary's 500km cap — this triggers real ingestion work

poiRouter.post(
  "/api/poi/ingest",
  asyncHandler(async (req, res) => {
    const jwt = bearerToken(req);
    if (jwt === null) {
      return res.status(401).json({ error: "unauthorized" });
    }

    const userClient = getUserClient(jwt);

    let user;
    try {
      const { data, error } = await userClient.auth.getUser(jwt);
      if (error) throw error;
      user = data.user;
    } catch {
      return res.status(401).json({ error: "unauthorized" });
    }

    if (!user) {
      return res.status(401).json({ error: "unauthorized" });
    }

    const admin = getAdminClient();
    const allowed = await unwrap(
      admin.rpc("check_rate_limit", {
        p_user: user.id,
        p_action: "ingest_poi",
        p_max: 1000,
        p_window: "1 day",
      }),
    );

    if (!allowed) {
      return res
        .status(429)
        .json({ error: "rate_limit_exceeded", message: "Too many ingest requests today" });
    }

    const body = (req.body ?? {}) as Record<string, unknown>;

    const lat = Number(body.lat);
    const lng = Number(body.lng);
    if (body.lat === undefined || body.lng === undefined || !Number.isFinite(lat) || !Number.isFinite(lng)) {
      return res
        .status(400)
        .json({ error: "bad_request", message: "lat and lng are required numbers" });
    }

    if (!(lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180)) {
      return res.status(400).json({ error: "bad_request", message: "lat/lng out of range" });
    }

    const radiusKm = Math.min(Number(body.radius_km ?? 5), MAX_RADIUS_KM);

    let summary;
    try {
      summary = await ensureTilesIngested(lat, lng, radiusKm);
    } catch (error) {
      if (error instanceof ConfigurationError) {
        // requireServiceRoleKey() raises this when the key is unset —
        // the one manual-config case worth a distinct status code for.
        return res.status(503).json({ error: "ingestion_unavailable", message: error.message });
      }
      logger.exception(`Ingestion request failed for (${lat}, ${lng}, ${radiusKm}km)`, error);
      return res.status(502).json({
        error: "ingestion_failed",
        message: error instanceof Error ? error.message : String(error),
      });
    }

    return res.json(summary);
  }),
);
