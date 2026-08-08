/**
 * The error vocabulary Layer 1 translates into HTTP status codes.
 *
 * Layer 2 owns graceful degradation (spec §3), so anything reaching Layer 1 is
 * a state the orchestrator decided it could not recover from. Each class maps
 * to exactly one status code — see `routes/routes.ts`.
 */

export class RouteGenerationError extends Error {
  /** Machine-readable code the client switches on. */
  readonly code: string;
  readonly status: number;

  constructor(code: string, status: number, message: string) {
    super(message);
    this.name = new.target.name;
    this.code = code;
    this.status = status;
  }
}

/**
 * Thrown by every unimplemented stub in this module.
 *
 * Deliberately its own type rather than a bare `Error`: the fixture
 * orchestrator catches exactly this to decide "not built yet, serve the
 * placeholder", and must not swallow a real bug from a half-finished
 * implementation.
 */
export class NotImplementedError extends RouteGenerationError {
  constructor(what: string) {
    super(
      "not_implemented",
      501,
      `${what} is not implemented yet — see src/routeGeneration/README.md for the build order.`,
    );
  }
}

/** The city exists but is not open to traffic (`rollout_status = 'planning'`). */
export class CityNotAvailableError extends RouteGenerationError {
  constructor(cityId: string, status: string) {
    super("city_not_available", 409, `City ${cityId} is not available yet (rollout status: ${status}).`);
  }
}

export class CityNotFoundError extends RouteGenerationError {
  constructor(cityId: string) {
    super("city_not_found", 404, `No city with id ${cityId}.`);
  }
}

export class RouteNotFoundError extends RouteGenerationError {
  constructor(routeId: string) {
    super("route_not_found", 404, `No route with id ${routeId}.`);
  }
}

/** The theme/category filter matched nothing published in this city. */
export class NoEligiblePoisError extends RouteGenerationError {
  constructor(theme: string) {
    super("no_eligible_pois", 422, `No published POIs match the theme "${theme}" in this city.`);
  }
}

/** Even the single nearest POI's dwell time exceeds the stated budget. */
export class TimeBudgetTooShortError extends RouteGenerationError {
  constructor(minutes: number) {
    super(
      "time_budget_too_short",
      422,
      `A ${minutes}-minute budget is too short for any stop in this city.`,
    );
  }
}

/**
 * The provider failed or timed out *and* no cached matrix was available to
 * fall back on. With a cache hit this is never raised — that fallback is the
 * quota-aware handling in spec §8.
 */
export class RoutingProviderUnavailableError extends RouteGenerationError {
  constructor(provider: string, reason: string) {
    super("routing_provider_unavailable", 503, `Routing provider ${provider} unavailable: ${reason}`);
  }
}
