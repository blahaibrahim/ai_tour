import type { Coordinate } from '../models/coordinate.model.js';
import type {
  DurationMatrix,
  IsochronePolygon,
  LegMode,
  RouteResult,
} from '../models/routing.model.js';

/**
 * The single seam to the routing engine (Section 2/3). Domain code
 * depends only on this interface — never on a provider SDK directly —
 * which is what makes swapping GraphHopper for OpenRouteService, or for
 * a self-hosted OSRM/Valhalla instance later (Section 6), a one-file
 * change in adapters/routing-provider/, with zero changes to Domain or
 * Orchestration.
 *
 * Method signatures match Section 7. Return types are wrapped in
 * Promise<> — a deliberate addition beyond the doc's pseudocode, since
 * every one of these calls is a real network request to an external
 * provider (Section 6) and must be awaitable from day one.
 */
export interface RoutingProviderAdapter {
  getRoute(stops: Coordinate[], mode: LegMode): Promise<RouteResult>;
  getMatrix(points: Coordinate[], mode: LegMode): Promise<DurationMatrix>;
  getIsochrone(
    origin: Coordinate,
    timeBudgetMinutes: number,
    mode: LegMode,
  ): Promise<IsochronePolygon>;
}
