/**
 * The module's public face — the only thing Layer 1 is allowed to import.
 *
 * It also owns the fixture/real switch. `ROUTE_GENERATION_MODE=real` (the
 * default now that the orchestrator is implemented) runs the real pipeline;
 * `fixture` answers from `fixtures.ts`, which is kept for developing the app
 * against the contract with no database, no provider key and no network.
 *
 * The switch lives here rather than in the controller so that Layer 1 never
 * has to know which mode it is in — no endpoint changes either way.
 */
import { Config } from "../config";
import { getClient } from "../data/supabaseClient";
import { getLogger } from "../logger";
import { unwrap } from "../supabase";
import { getCityConfigRepository } from "./data/cityConfigRepository";
import { getPoiRepository } from "./data/poiRepository";
import { getProgressRepository, getRouteRepository } from "./data/routeRepository";
import { interpret as interpretPromptDomain } from "./domain/promptInterpreter";
import { categoriesForTheme } from "./domain/poiSelector";
import { CityNotAvailableError, CityNotFoundError, RouteNotFoundError } from "./errors";
import {
  FIXTURE_CATEGORIES,
  FIXTURE_CITIES,
  FIXTURE_THEMES,
  fixturePromptInterpretation,
  fixtureRefinedRoute,
  fixtureRoute,
} from "./fixtures";
import * as orchestrator from "./orchestrator";
import {
  Category,
  CityConfig,
  Locale,
  Progress,
  PromptInterpretation,
  PromptInterpretationRequest,
  RouteRequest,
  RouteResponse,
  RouteSummary,
  Theme,
} from "./types";

const logger = getLogger("routeGeneration");

export type RouteGenerationMode = "fixture" | "real";

export const MODE: RouteGenerationMode =
  Config.ROUTE_GENERATION_MODE === "fixture" ? "fixture" : "real";

if (MODE === "fixture") {
  logger.warning(
    "ROUTE GENERATION IS SERVING FIXTURES. Every route is invented — set " +
      "ROUTE_GENERATION_MODE=real in backend/.env to run the real pipeline.",
  );
}

const ROUTABLE_STATUSES = new Set(["pilot", "active"]);

export async function listCities(): Promise<CityConfig[]> {
  if (MODE === "fixture") return FIXTURE_CITIES;
  return getCityConfigRepository().listAll();
}

export async function listCategories(): Promise<Category[]> {
  if (MODE === "fixture") return FIXTURE_CATEGORIES;
  return getPoiRepository().listCategories();
}

/**
 * Themes the request builder may offer.
 *
 * Scoped to a city when one is known, because the answer genuinely differs:
 * `themes_available` only returns a theme whose categories hold at least one
 * published POI in that city. That is what stops the picker offering a theme
 * which can only ever answer 422 — the traveller reads an empty result as
 * "there is nothing here" rather than "we should not have offered that".
 */
export async function listThemes(cityId?: string): Promise<Theme[]> {
  if (MODE === "fixture") return FIXTURE_THEMES;

  const rows =
    (await unwrap<Array<{ key: string; label_en: string; label_fr: string; label_ar: string }>>(
      getClient().rpc("themes_available", { p_city_id: cityId ?? null }),
    )) ?? [];

  return rows.map((r) => ({
    key: r.key,
    labelEn: r.label_en,
    labelFr: r.label_fr,
    labelAr: r.label_ar,
  }));
}

/**
 * Turns free text into a theme plus preferred categories, grounded against
 * `cityId`'s real vocabulary (see `domain/promptInterpreter.ts` for the
 * enforcement and `POST /api/routes/interpret` in `routes/routes.ts` for the
 * request shape).
 *
 * Never throws for "the model got it wrong" or "Groq is down" — both surface
 * as `understood: false`, and the caller falls back to whatever theme is
 * already selected with no preferred categories, exactly as if the
 * traveller had typed nothing. Themes are optional end to end; a failed
 * interpretation is not a failure of the request.
 */
export async function interpretPrompt(
  request: PromptInterpretationRequest,
): Promise<PromptInterpretation> {
  if (MODE === "fixture") return fixturePromptInterpretation(request.prompt);

  const [themes, categories] = await Promise.all([
    listThemes(request.cityId),
    getPoiRepository().listAvailableCategories(request.cityId, request.theme),
  ]);

  return interpretPromptDomain(
    {
      prompt: request.prompt,
      locale: request.locale ?? "en",
      themes: themes.map((t) => ({ key: t.key, labelEn: t.labelEn })),
      categories: categories.map((c) => ({ key: c.key, labelEn: c.labelEn, poiCount: c.poiCount })),
    },
    { categoriesForTheme: (themeKey) => categoriesForTheme(request.cityId, themeKey) },
  );
}

/** Shared by both modes, so the rollout gate is enforced identically. */
async function assertRoutable(cityId: string): Promise<void> {
  const cities = await listCities();
  const city = cities.find((c) => c.id === cityId);
  if (!city) throw new CityNotFoundError(cityId);
  if (!ROUTABLE_STATUSES.has(city.rolloutStatus)) {
    throw new CityNotAvailableError(cityId, city.rolloutStatus);
  }
}

export async function generateRoute(request: RouteRequest): Promise<RouteResponse> {
  if (MODE === "fixture") {
    await assertRoutable(request.cityId);
    return fixtureRoute(request);
  }
  return orchestrator.generateRoute(request);
}

/** NOT IN SPEC — see the note on `orchestrator.refineRoute`. */
export async function refineRoute(
  routeId: string,
  dropPoiIds: string[],
  request: RouteRequest,
): Promise<RouteResponse> {
  if (MODE === "fixture") {
    await assertRoutable(request.cityId);
    return fixtureRefinedRoute(request, dropPoiIds);
  }
  return orchestrator.refineRoute(routeId, dropPoiIds, request);
}

export async function getRoute(
  routeId: string,
  userId: string | null,
  locale: Locale = "en",
): Promise<RouteResponse> {
  if (MODE === "fixture") {
    return fixtureRoute({
      cityId: FIXTURE_CITIES[0].id,
      theme: "history",
      timeBudgetMinutes: 240,
      transportMode: "hybrid",
    });
  }
  const route = await getRouteRepository().findById(routeId, userId, locale);
  // Not-found and not-yours are deliberately the same answer: distinguishing
  // them tells an unauthorised caller that a given route id exists.
  if (!route) throw new RouteNotFoundError(routeId);
  return route;
}

/**
 * The caller's past routes, newest first.
 *
 * Capped rather than paged. A traveller with hundreds of routes is not a case
 * this app has, and a limit is one parameter where a cursor is a contract —
 * when it becomes one, that is the moment to add paging rather than now.
 */
export async function listRoutes(userId: string, limit = 20): Promise<RouteSummary[]> {
  if (MODE === "fixture") {
    // One entry, so the history screen can be developed against something. It
    // is the same route `getRoute` serves in this mode, summarised, rather than
    // an invented second one that would open as something else.
    const route = fixtureRoute({
      cityId: FIXTURE_CITIES[0].id,
      theme: "history",
      timeBudgetMinutes: 240,
      transportMode: "hybrid",
    });
    return [
      {
        id: route.id,
        cityId: route.cityId,
        cityName: FIXTURE_CITIES[0].name,
        theme: route.theme,
        transportMode: route.transportMode,
        timeBudgetMinutes: route.timeBudgetMinutes,
        estimatedTotalDurationMinutes: route.estimatedTotalDurationMinutes,
        dayCountFlag: route.dayCountFlag,
        stopCount: route.stops.length,
        generatedAt: route.generatedAt,
      },
    ];
  }
  return getRouteRepository().listForUser(userId, limit);
}

export async function startProgress(routeId: string): Promise<Progress> {
  if (MODE === "fixture") {
    const now = new Date().toISOString();
    return {
      id: "ab000000-0000-4000-8000-0000000000aa",
      routeId,
      status: "in_progress",
      startedAt: now,
      lastUpdatedAt: now,
      completedAt: null,
      visitedPoiIds: [],
    };
  }
  return getProgressRepository().start(routeId);
}

export async function getProgress(progressId: string): Promise<Progress | null> {
  if (MODE === "fixture") {
    const now = new Date().toISOString();
    return {
      id: progressId,
      routeId: "fa000000-0000-4000-8000-0000000000ff",
      status: "in_progress",
      startedAt: now,
      lastUpdatedAt: now,
      completedAt: null,
      visitedPoiIds: [],
    };
  }
  return getProgressRepository().findById(progressId);
}

export async function recordCheckpoint(
  progressId: string,
  poiId: string,
): Promise<{ progressId: string; poiId: string; arrivedAt: string }> {
  if (MODE === "fixture") {
    return { progressId, poiId, arrivedAt: new Date().toISOString() };
  }
  const event = await getProgressRepository().recordCheckpoint(progressId, poiId);
  return { progressId: event.progressId, poiId: event.poiId, arrivedAt: event.arrivedAt };
}

export * from "./types";
export { RouteGenerationError, NotImplementedError } from "./errors";
