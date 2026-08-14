import type { Coordinate, GeoJsonPolygon } from '../../domain/models/coordinate.model.js';
import type {
  DurationMatrix,
  IsochronePolygon,
  LegMode,
  RouteResult,
} from '../../domain/models/routing.model.js';
import type { RoutingProviderAdapter } from '../../domain/ports/routing-provider-adapter.port.js';
import { RoutingProviderError } from './errors.js';

export interface GraphHopperAdapterConfig {
  apiKey: string;
  /** Default: the hosted GraphHopper Directions API. Overridable to point
   * at a self-hosted instance later (Section 6's future scale path) —
   * the self-hosted open-source server implements the same /route and
   * /isochrone shapes, though its Matrix endpoint differs; a self-hosted
   * swap would land as its own adapter class, not a baseUrl override, but
   * the seam is here for local testing against `graphhopper/graphhopper`. */
  baseUrl?: string;
  /** Section 8: "Adapter enforces a timeout". Default 3000ms. */
  timeoutMs?: number;
  /** Injectable for tests — defaults to the global fetch. */
  fetchImpl?: typeof fetch;
}

/** GraphHopper vehicle/profile identifiers for the two LegModes this module uses. */
const PROFILE_BY_MODE: Record<LegMode, string> = {
  driving: 'car',
  walking: 'foot',
};

interface GraphHopperRoutePath {
  distance: number;
  time: number;
  points?: { type: string; coordinates: number[][] };
}

interface GraphHopperRouteResponse {
  paths: GraphHopperRoutePath[];
}

interface GraphHopperMatrixResponse {
  times: number[][];
  distances: number[][];
}

interface GraphHopperIsochronePolygonFeature {
  type: string;
  properties?: { bucket: number };
  geometry: GeoJsonPolygon;
}

interface GraphHopperIsochroneResponse {
  polygons: GraphHopperIsochronePolygonFeature[];
}

/**
 * RoutingProviderAdapter implementation for the hosted GraphHopper
 * Directions API (Section 6) — the primary provider, chosen for its
 * no-credit-card free tier. Endpoint paths and payload shapes below
 * match GraphHopper's current documented Routing, Matrix, and Isochrone
 * APIs (docs.graphhopper.com), verified against their reference docs
 * and concrete request/response examples — not assumed from memory.
 *
 * Domain never imports this class directly (Section 2) — only the
 * RoutingProviderAdapter port it implements.
 */
export class GraphHopperAdapter implements RoutingProviderAdapter {
  private readonly apiKey: string;
  private readonly baseUrl: string;
  private readonly timeoutMs: number;
  private readonly fetchImpl: typeof fetch;

  constructor(config: GraphHopperAdapterConfig) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl ?? 'https://graphhopper.com/api/1';
    this.timeoutMs = config.timeoutMs ?? 3000;
    this.fetchImpl = config.fetchImpl ?? fetch;
  }

  async getRoute(stops: Coordinate[], mode: LegMode): Promise<RouteResult> {
    const params = new URLSearchParams();
    for (const stop of stops) {
      params.append('point', `${stop.lat},${stop.lng}`);
    }
    params.set('profile', PROFILE_BY_MODE[mode]);
    // Plain [lon,lat] coordinates instead of an encoded polyline — trades
    // a little bandwidth for not needing a polyline-decoding dependency.
    params.set('points_encoded', 'false');
    params.set('key', this.apiKey);

    const json = await this.request<GraphHopperRouteResponse>(
      `${this.baseUrl}/route?${params.toString()}`,
      { method: 'GET' },
    );

    const path = json.paths[0];
    if (!path || typeof path.distance !== 'number' || typeof path.time !== 'number') {
      throw new RoutingProviderError(
        'GraphHopper /route response missing expected paths[0] fields',
        'invalid_response',
        'graphhopper',
      );
    }

    const geometry: Coordinate[] = Array.isArray(path.points?.coordinates)
      ? path.points.coordinates.map(lngLatToCoordinate)
      : [];

    return {
      mode,
      durationMinutes: path.time / 60_000,
      distanceMeters: path.distance,
      geometry,
    };
  }

  async getMatrix(points: Coordinate[], mode: LegMode): Promise<DurationMatrix> {
    const body = {
      from_points: points.map(coordinateToLngLat),
      to_points: points.map(coordinateToLngLat),
      out_arrays: ['times', 'distances'],
      // The Matrix API's concrete examples use `vehicle`, not `profile`
      // (unlike the Routing API) — this is GraphHopper's own API
      // asymmetry, not an inconsistency in this adapter.
      vehicle: PROFILE_BY_MODE[mode],
    };

    const json = await this.request<GraphHopperMatrixResponse>(
      `${this.baseUrl}/matrix?key=${this.apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      },
    );

    if (!Array.isArray(json.times) || !Array.isArray(json.distances)) {
      throw new RoutingProviderError(
        'GraphHopper /matrix response missing expected times/distances arrays',
        'invalid_response',
        'graphhopper',
      );
    }

    return {
      points,
      mode,
      durationsMinutes: json.times.map((row) => row.map((seconds) => seconds / 60)),
      distancesMeters: json.distances,
    };
  }

  async getIsochrone(
    origin: Coordinate,
    timeBudgetMinutes: number,
    mode: LegMode,
  ): Promise<IsochronePolygon> {
    const params = new URLSearchParams({
      point: `${origin.lat},${origin.lng}`,
      time_limit: String(Math.round(timeBudgetMinutes * 60)),
      profile: PROFILE_BY_MODE[mode],
      buckets: '1',
      key: this.apiKey,
    });

    const json = await this.request<GraphHopperIsochroneResponse>(
      `${this.baseUrl}/isochrone?${params.toString()}`,
      { method: 'GET' },
    );

    const polygon = json.polygons[0]?.geometry;
    if (!polygon || polygon.type !== 'Polygon') {
      throw new RoutingProviderError(
        'GraphHopper /isochrone response missing expected polygons[0].geometry',
        'invalid_response',
        'graphhopper',
      );
    }

    return { center: origin, timeBudgetMinutes, mode, polygon };
  }

  /**
   * Shared fetch wrapper. Enforces this.timeoutMs (Section 8) and
   * normalizes every failure mode into RoutingProviderError so callers
   * can distinguish timeout / HTTP failure / bad payload.
   *
   * Retries up to 3 times on HTTP 429 (rate limit) with exponential
   * backoff — the GraphHopper free tier has strict per-minute caps and
   * the orchestrator issues many calls per generate request.
   *
   * Deliberately does NOT fall back to cache here — that's
   * Orchestration's job (Section 3: "owns graceful degradation"), not
   * the Adapter's. This method's only job is: succeed with parsed JSON,
   * or throw.
   */
  private async request<T>(url: string, init: RequestInit): Promise<T> {
    const MAX_RETRIES = 3;
    const BASE_DELAY_MS = 2000;

    // Inter-request delay to stay under the per-second rate limit.
    // The free tier allows ~5 req/s but penalises bursts aggressively.
    // Increased to 1500ms to guarantee we stay under the penalty threshold.
    await sleep(1500);

    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), this.timeoutMs);

      let response: Response;
      try {
        response = await this.fetchImpl(url, { ...init, signal: controller.signal });
      } catch (err) {
        clearTimeout(timer);
        if (err instanceof Error && err.name === 'AbortError') {
          throw new RoutingProviderError(
            `GraphHopper request timed out after ${this.timeoutMs}ms`,
            'timeout',
            'graphhopper',
            { cause: err },
          );
        }
        throw new RoutingProviderError(
          'GraphHopper request failed',
          'request_failed',
          'graphhopper',
          { cause: err },
        );
      } finally {
        clearTimeout(timer);
      }

      // Retry on rate limit (429) with exponential backoff.
      if (response.status === 429 && attempt < MAX_RETRIES) {
        const delay = BASE_DELAY_MS * Math.pow(2, attempt);
        await sleep(delay);
        continue;
      }

      if (!response.ok) {
        const errorBody = await response.text().catch(() => '');
        throw new RoutingProviderError(
          `GraphHopper returned HTTP ${response.status}: ${errorBody}`,
          'request_failed',
          'graphhopper',
        );
      }

      try {
        return (await response.json()) as T;
      } catch (err) {
        throw new RoutingProviderError(
          'GraphHopper returned invalid JSON',
          'invalid_response',
          'graphhopper',
          { cause: err },
        );
      }
    }

    // Should never reach here, but just in case:
    throw new RoutingProviderError(
      'GraphHopper rate limit exceeded after retries',
      'request_failed',
      'graphhopper',
    );
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function coordinateToLngLat(c: Coordinate): [number, number] {
  return [c.lng, c.lat];
}

function lngLatToCoordinate(pair: number[]): Coordinate {
  const [lng, lat] = pair;
  return { lat: lat ?? 0, lng: lng ?? 0 };
}
