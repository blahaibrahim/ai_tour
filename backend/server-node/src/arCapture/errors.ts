/**
 * The error vocabulary Layer 1 translates into HTTP status codes.
 *
 * Same shape as `routeGeneration/errors.ts`: each class maps to exactly one
 * status code, and `NotImplementedError` is its own type so the fixture/real
 * switch in `index.ts` can catch precisely "not built yet" rather than
 * swallowing a real bug.
 */

export class ArCaptureError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, status: number, message: string) {
    super(message);
    this.name = new.target.name;
    this.code = code;
    this.status = status;
  }
}

export class NotImplementedError extends ArCaptureError {
  constructor(what: string) {
    super(
      "not_implemented",
      501,
      `${what} is not implemented yet — see src/arCapture/README.md for the build order.`,
    );
  }
}

export class RouteNotFoundError extends ArCaptureError {
  constructor(routeId: string) {
    super("route_not_found", 404, `No route with id ${routeId}.`);
  }
}

export class SpawnNotFoundError extends ArCaptureError {
  constructor(spawnId: string) {
    super("spawn_not_found", 404, `No mascot spawn with id ${spawnId}.`);
  }
}

export class MascotNotFoundError extends ArCaptureError {
  constructor(mascotId: string) {
    super("mascot_not_found", 404, `No mascot with id ${mascotId}.`);
  }
}

/** First-failure-short-circuits validator outcomes (plan §5.7) are returned
 * as data, not thrown — this is for genuinely exceptional request shapes. */
export class InvalidCaptureRequestError extends ArCaptureError {
  constructor(message: string) {
    super("bad_request", 400, message);
  }
}
