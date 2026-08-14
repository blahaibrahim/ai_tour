import type { Coordinate } from '../../src/domain/models/coordinate.model.js';
import type {
  DurationMatrix,
  IsochronePolygon,
  LegMode,
  RouteResult,
} from '../../src/domain/models/routing.model.js';
import type { RoutingProviderAdapter } from '../../src/domain/ports/routing-provider-adapter.port.js';

/**
 * Deterministic stub used across automated test runs (Section 11:
 * "A mock/stub adapter is used for all automated test runs to avoid
 * consuming free-tier quota"). Distances/durations are synthetic —
 * proportional to point index, not real geography — good enough for
 * exercising Domain and Cache logic without a network call.
 */
export class MockRoutingProviderAdapter implements RoutingProviderAdapter {
  async getRoute(stops: Coordinate[], mode: LegMode): Promise<RouteResult> {
    return {
      mode,
      durationMinutes: stops.length * 5,
      distanceMeters: stops.length * 400,
      geometry: stops,
    };
  }

  async getMatrix(points: Coordinate[], mode: LegMode): Promise<DurationMatrix> {
    const n = points.length;
    const durationsMinutes = Array.from({ length: n }, (_, i) =>
      Array.from({ length: n }, (_, j) => (i === j ? 0 : Math.abs(i - j) * 5)),
    );
    const distancesMeters = Array.from({ length: n }, (_, i) =>
      Array.from({ length: n }, (_, j) => (i === j ? 0 : Math.abs(i - j) * 400)),
    );
    return { points, mode, durationsMinutes, distancesMeters };
  }

  async getIsochrone(
    origin: Coordinate,
    timeBudgetMinutes: number,
    mode: LegMode,
  ): Promise<IsochronePolygon> {
    const delta = 0.01;
    return {
      center: origin,
      timeBudgetMinutes,
      mode,
      polygon: {
        type: 'Polygon',
        coordinates: [
          [
            [origin.lng - delta, origin.lat - delta],
            [origin.lng + delta, origin.lat - delta],
            [origin.lng + delta, origin.lat + delta],
            [origin.lng - delta, origin.lat + delta],
            [origin.lng - delta, origin.lat - delta],
          ],
        ],
      },
    };
  }
}
