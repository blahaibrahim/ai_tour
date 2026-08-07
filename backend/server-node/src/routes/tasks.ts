/**
 * Feature 3 from docs/backend/08 — per-location task generation.
 *
 * The safety instruction below isn't boilerplate: a model asked for "creative
 * challenges" at, say, a 175m suspension bridge will cheerfully suggest
 * something that gets someone hurt. Constrain it, then validate the shape
 * server-side before it ever reaches the app.
 */
import { Router } from "express";

import { getLocation } from "../data/locationsRepo";
import { extractJson, JsonExtractionError } from "../jsonUtils";
import { chat, LLMError } from "../llm";
import { authenticateAndRateLimit } from "../rateLimit";
import { asyncHandler } from "./asyncHandler";

export const tasksRouter = Router();

const ALLOWED_TASK_TYPES = new Set(["mascot", "video", "scan", "photo"]);
const MIN_POINTS = 10;
const MAX_POINTS = 100;

tasksRouter.post(
  "/api/tasks/generate",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "generate_task", 50, "1 hour");
    if (auth.failure) {
      return res.status(auth.failure.status).json(auth.failure.body);
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    const locationId = body.location_id;

    if (!locationId) {
      return res.status(400).json({ error: "bad_request", message: "location_id is required" });
    }

    const location = await getLocation(String(locationId));
    if (location === null) {
      return res.status(404).json({ error: "location_not_found" });
    }

    const messages = [
      {
        role: "system" as const,
        content:
          "Generate one photo/video/scan challenge for a traveller at " +
          "the given location. It must be doable in under 10 minutes, " +
          "on foot, with a phone. Do not suggest entering restricted " +
          "areas, climbing anything, trespassing, or any other unsafe " +
          "act. Reply with a single JSON object shaped exactly like: " +
          '{"type": "mascot|video|scan|photo", "label": "...", ' +
          '"points": 20}. No prose outside the JSON.',
      },
      {
        role: "user" as const,
        content:
          `${location.name} (${location.category}, ${location.region}). ` + `${location.blurb}`,
      },
    ];

    let parsed: Record<string, unknown>;
    try {
      const raw = await chat(messages, { jsonMode: true, maxTokens: 300, temperature: 0.8 });
      parsed = extractJson(raw);
    } catch (error) {
      if (error instanceof LLMError) {
        return res.status(503).json({ error: "llm_unavailable", message: error.message });
      }
      if (error instanceof JsonExtractionError) {
        return res.status(502).json({ error: "llm_bad_output", message: error.message });
      }
      throw error;
    }

    const taskType = parsed.type;
    const label = String(parsed.label ?? "")
      .trim()
      .slice(0, 200);
    const rawPoints = parsed.points;

    if (typeof taskType !== "string" || !ALLOWED_TASK_TYPES.has(taskType) || !label) {
      return res
        .status(502)
        .json({ error: "llm_bad_output", message: "Generated task failed validation" });
    }

    const parsedPoints = Number.parseInt(String(rawPoints), 10);
    const points = Number.isNaN(parsedPoints)
      ? 30
      : Math.max(MIN_POINTS, Math.min(parsedPoints, MAX_POINTS));

    return res.json({ type: taskType, label, points });
  }),
);
