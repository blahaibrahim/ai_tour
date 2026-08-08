/**
 * The module's public face — the only thing Layer 1 is allowed to import.
 *
 * It also owns the fixture/real switch. While `ROUTE_GENERATION_MODE=fixture`
 * (the default, because the module is not built yet) every call here answers
 * from `fixtures.ts`; set it to `real` and the same calls go to the
 * orchestrator, which throws NotImplementedError at the first missing piece.
 *
 * The switch lives here rather than in the controller so that Layer 1 never
 * has to know the module is a skeleton — when the orchestrator is finished,
 * the default flips and no endpoint changes.
 */
import { getLogger } from "../logger";
import { getCityConfigRepository } from "./data/cityConfigRepository";
import { getPoiRepository } from "./data/poiRepository";
import { getProgressRepository, getRouteRepository } from "./data/routeRepository";
import { CityNotAvailableError, CityNotFoundError, RouteNotFoundError } from "./errors";
import {
  FIXTURE_CATEGORIES,
  FIXTURE_CITIES,
  FIXTURE_THEMES,
  fixtureRefinedRoute,
  fixtureRoute,
} from "./fixtures";
import * as orchestrator from "./orchestrator";
import { Category, CityConfig, Progress, RouteRequest, RouteResponse } from "./types";

const logger = getLogger("routeGeneration");

export type RouteGenerationMode = "fixture" | "real";

export const MODE: RouteGenerationMode =
  process.env.ROUTE_GENERATION_MODE === "real" ? "real" : "fixture";

if (MODE === "fixture") {
  logger.warning(
    "ROUTE GENERATION IS SERVING FIXTURES. The module is a skeleton — see " +
      "src/routeGeneration/README.md. Set ROUTE_GENERATION_MODE=real once the " +
      "orchestrator is implemented.",
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

export async function listThemes(): Promise<typeof FIXTURE_THEMES> {
  // Themes have no table in the spec's schema — see poiSelector.ts. Until they
  // do, this is the same list in both modes rather than a silent difference.
  return FIXTURE_THEMES;
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
): Promise<RouteResponse> {
  if (MODE === "fixture") {
    return fixtureRoute({
      cityId: FIXTURE_CITIES[0].id,
      theme: "history",
      timeBudgetMinutes: 240,
      transportMode: "hybrid",
    });
  }
  const route = await getRouteRepository().findById(routeId, userId);
  if (!route) throw new RouteNotFoundError(routeId);
  return route;
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
