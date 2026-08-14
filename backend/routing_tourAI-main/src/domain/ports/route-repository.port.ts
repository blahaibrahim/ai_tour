import type { PersistedRoute, RouteResponse } from '../models/route.model.js';

/**
 * Access to the immutable `routes` + `route_stops` tables (Section 3/7).
 * `save` is the only write — routes are never updated after generation,
 * only ever created (mutable state lives in ProgressRepository instead,
 * kept deliberately separate per Section 3).
 */
export interface RouteRepository {
  save(
    route: RouteResponse,
    context: { sessionId?: string; userId?: string },
  ): Promise<PersistedRoute>;
  findById(id: string): Promise<PersistedRoute | null>;
}
