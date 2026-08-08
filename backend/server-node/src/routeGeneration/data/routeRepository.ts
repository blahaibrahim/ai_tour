/**
 * Layer 5 — Route / Progress Repository.
 *
 * Immutable route definitions kept strictly separate from mutable progress
 * state (spec §3). A route is written once at generation and never updated;
 * everything that changes as the traveller walks lives in `progress` and the
 * append-only `progress_events`.
 *
 * That separation is what makes `route_stops` safe to query for the
 * data-flywheel work later — "which POIs actually appear in routes" is a fact
 * about the generated route, not about anyone's walk.
 *
 * STATUS: stubs.
 */
import { NotImplementedError } from "../errors";
import { Progress, ProgressEvent, RouteResponse } from "../types";

export interface PersistRouteInput {
  route: RouteResponse;
  userId: string | null;
  sessionId: string | null;
}

export interface RouteRepository {
  /**
   * Writes the `routes` row and its `route_stops` children in one transaction.
   * Returns the persisted id — which becomes `RouteResponse.id`, so the
   * assembler's provisional id is replaced here rather than the other way
   * round.
   */
  persist(input: PersistRouteInput): Promise<string>;

  /** Rehydrates a route, joining `route_stops` back onto `pois`. */
  findById(routeId: string, userId: string | null): Promise<RouteResponse | null>;

  /** The caller's most recent route — what "resume my tour" reads. */
  findLatestForUser(userId: string): Promise<RouteResponse | null>;
}

export interface ProgressRepository {
  start(routeId: string): Promise<Progress>;
  findById(progressId: string): Promise<Progress | null>;
  findByRouteId(routeId: string): Promise<Progress | null>;

  /**
   * Appends a checkpoint. Append-only by design: an arrival is an event that
   * happened, not a flag to be toggled, and re-arriving at a stop is a real
   * thing that should not overwrite the first visit.
   *
   * Whether the traveller was actually inside `checkpoint_radius_meters` is
   * decided by the separate AR trigger service, along with the
   * dwell-time-before-confirm logic (spec §10) — this only records it.
   */
  recordCheckpoint(progressId: string, poiId: string): Promise<ProgressEvent>;

  updateStatus(progressId: string, status: Progress["status"]): Promise<Progress>;
}

class SupabaseRouteRepository implements RouteRepository {
  persist(_input: PersistRouteInput): Promise<string> {
    throw new NotImplementedError("RouteRepository.persist");
  }
  findById(_routeId: string, _userId: string | null): Promise<RouteResponse | null> {
    throw new NotImplementedError("RouteRepository.findById");
  }
  findLatestForUser(_userId: string): Promise<RouteResponse | null> {
    throw new NotImplementedError("RouteRepository.findLatestForUser");
  }
}

class SupabaseProgressRepository implements ProgressRepository {
  start(_routeId: string): Promise<Progress> {
    throw new NotImplementedError("ProgressRepository.start");
  }
  findById(_progressId: string): Promise<Progress | null> {
    throw new NotImplementedError("ProgressRepository.findById");
  }
  findByRouteId(_routeId: string): Promise<Progress | null> {
    throw new NotImplementedError("ProgressRepository.findByRouteId");
  }
  recordCheckpoint(_progressId: string, _poiId: string): Promise<ProgressEvent> {
    throw new NotImplementedError("ProgressRepository.recordCheckpoint");
  }
  updateStatus(_progressId: string, _status: Progress["status"]): Promise<Progress> {
    throw new NotImplementedError("ProgressRepository.updateStatus");
  }
}

let sharedRoutes: RouteRepository | null = null;
let sharedProgress: ProgressRepository | null = null;

export function getRouteRepository(): RouteRepository {
  if (sharedRoutes === null) sharedRoutes = new SupabaseRouteRepository();
  return sharedRoutes;
}

export function getProgressRepository(): ProgressRepository {
  if (sharedProgress === null) sharedProgress = new SupabaseProgressRepository();
  return sharedProgress;
}
