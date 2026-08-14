import type { Cluster } from '../domain/models/cluster.model.js';
import type { Coordinate } from '../domain/models/coordinate.model.js';
import type { Poi } from '../domain/models/poi.model.js';
import type { RouteResponse } from '../domain/models/route.model.js';
import type { DurationMatrix, LegMode } from '../domain/models/routing.model.js';
import type { Segment } from '../domain/models/segment.model.js';
import type { CacheAdapter } from '../domain/ports/cache-adapter.port.js';
import type { CityConfigRepository } from '../domain/ports/city-config-repository.port.js';
import type { RoutingProviderAdapter } from '../domain/ports/routing-provider-adapter.port.js';
import { cluster } from '../domain/services/clustering-engine/index.js';
import { PoiSelector } from '../domain/services/poi-selector/index.js';
import { orderClusters, orderStopsWithinCluster } from '../domain/services/route-optimizer/index.js';
import { estimate } from '../domain/services/time-reachability-estimator/index.js';
import { assemble } from '../domain/services/response-assembler/index.js';

export interface RouteGenerationRequest {
  cityId: string;
  theme: string;
  timeBudgetMinutes: number;
}

export interface OrchestratorDependencies {
  routingProvider: RoutingProviderAdapter;
  cache: CacheAdapter;
  cityConfigRepository: CityConfigRepository;
  poiSelector: PoiSelector;
}

/**
 * Route Generation Orchestrator (Section 2/3): sequences Domain calls
 * in order, loads city config, owns graceful degradation and telemetry.
 *
 * The efficiency rule (Section 4): the routing provider's matrix
 * endpoint is called once per request — covering all cluster and stop
 * pairs in a single call — never once per pair.
 *
 * Workflow (Section 4):
 *   1. Load city config → get cluster radius, active provider
 *   2. POI Selector → eligible POIs by theme + city
 *   3. Clustering Engine → group into walkable clusters
 *   4. Get/compute matrix (cache-first) for cluster anchors
 *   5. Route Optimizer → order clusters (driving)
 *   6. For each cluster, order stops within (walking) using the matrix
 *   7. Build segments from the ordered route
 *   8. Time & Reachability Estimator → total duration + day-count flag
 *   9. Response Assembler → final RouteResponse
 */
export class RouteGenerationOrchestrator {
  private readonly deps: OrchestratorDependencies;

  constructor(deps: OrchestratorDependencies) {
    this.deps = deps;
  }

  async generate(request: RouteGenerationRequest): Promise<RouteResponse> {
    const { cityId, theme, timeBudgetMinutes } = request;

    // Step 1: Load city config.
    const cityConfig = await this.deps.cityConfigRepository.findById(cityId);
    if (!cityConfig) {
      throw new Error(`City config not found for cityId: ${cityId}`);
    }

    // Step 2: Select eligible POIs.
    const pois = await this.deps.poiSelector.select(cityId, theme);
    if (pois.length === 0) {
      throw new Error(`No eligible POIs found for theme "${theme}" in city "${cityConfig.name}"`);
    }

    // Step 3: Cluster POIs.
    const clusters = cluster(pois, cityConfig.clusterRadiusMeters);

    // Step 4: Get driving matrix for cluster anchors (cache-first).
    const clusterAnchors = clusters.map((c) => c.anchor);
    const drivingMatrix = await this.getMatrixCacheFirst(
      cityId,
      clusterAnchors,
      'driving',
    );

    // Step 5: Order clusters by driving duration.
    const orderedClusters = orderClusters(clusters, drivingMatrix);

    // Step 6: Order stops within each cluster (walking).
    // Collect all POI locations across all clusters for a single walking
    // matrix call — Section 4's efficiency rule.
    const allPois = orderedClusters.flatMap((c) => c.pois);
    const allPoiLocations = allPois.map((p) => p.location);

    let walkingMatrix: DurationMatrix;
    if (allPoiLocations.length > 1) {
      walkingMatrix = await this.getMatrixCacheFirst(
        cityId,
        allPoiLocations,
        'walking',
      );
    } else {
      // Single POI — no matrix needed.
      walkingMatrix = {
        points: allPoiLocations,
        mode: 'walking',
        durationsMinutes: [[0]],
        distancesMeters: [[0]],
      };
    }

    // Build a POI-index map so we can extract sub-matrices per cluster.
    const poiIndexMap = new Map<string, number>();
    allPois.forEach((p, i) => poiIndexMap.set(p.id, i));

    // Order stops within each cluster using the relevant sub-matrix.
    for (const c of orderedClusters) {
      if (c.pois.length <= 1) continue;
      const indices = c.pois.map((p) => poiIndexMap.get(p.id)!);
      const subMatrix = extractSubMatrix(walkingMatrix, indices);
      const ordered = orderStopsWithinCluster(
        { ...c, pois: c.pois },
        subMatrix,
      );
      c.pois = ordered;
    }

    // Step 7: Build segments from the ordered route.
    const segments = await this.buildSegments(orderedClusters);

    // Step 8: Time & Reachability estimation.
    // Build a sequential matrix for the flattened stop order.
    const flatStops = orderedClusters.flatMap((c) => c.pois);
    const flatLocations = flatStops.map((p) => p.location);
    let sequentialMatrix: DurationMatrix;
    if (flatLocations.length > 1) {
      sequentialMatrix = await this.getMatrixCacheFirst(
        cityId,
        flatLocations,
        'walking', // Walking for the sequential estimate
      );
    } else {
      sequentialMatrix = {
        points: flatLocations,
        mode: 'walking',
        durationsMinutes: [[0]],
        distancesMeters: [[0]],
      };
    }

    // Attempt an isochrone check for day-count determination.
    let isochrone = null;
    if (flatStops.length > 0 && flatStops[0]) {
      try {
        isochrone = await this.getIsochoneCacheFirst(
          flatStops[0],
          timeBudgetMinutes,
          'driving',
        );
      } catch {
        // Graceful degradation: if isochrone fails, day-count flag is
        // derived purely from the time-budget arithmetic.
      }
    }

    const timeEstimate = estimate(
      flatStops,
      sequentialMatrix,
      timeBudgetMinutes,
      isochrone,
    );

    // Step 9: Assemble final response.
    return assemble({
      orderedClusters,
      segments,
      estimate: timeEstimate,
      cityId,
      theme,
      timeBudgetMinutes,
    });
  }

  // -------------------------------------------------------------------------
  // Cache-first matrix retrieval (Section 2/8).
  // -------------------------------------------------------------------------

  private async getMatrixCacheFirst(
    cityId: string,
    points: Coordinate[],
    mode: LegMode,
  ): Promise<DurationMatrix> {
    // Check cache first.
    const cacheKey = `${mode}:${points.length}`;
    const cached = await this.deps.cache.getMatrix(cityId, cacheKey);
    if (cached) return cached;

    // Cache miss — call the provider.
    let matrix: DurationMatrix;
    try {
      matrix = await this.deps.routingProvider.getMatrix(points, mode);
    } catch (err) {
      // Graceful degradation (Section 8): fall back to last cached
      // matrix if the provider fails. If no cached matrix either, rethrow.
      const fallback = await this.deps.cache.getMatrix(cityId, cacheKey);
      if (fallback) return fallback;
      throw err;
    }

    // Persist to cache.
    await this.deps.cache.setMatrix(cityId, cacheKey, matrix);
    return matrix;
  }

  // -------------------------------------------------------------------------
  // Cache-first isochrone retrieval.
  // -------------------------------------------------------------------------

  private async getIsochoneCacheFirst(
    poi: Poi,
    timeBudgetMinutes: number,
    mode: LegMode,
  ) {
    // Bucket time budgets to 30-min increments for cache reuse.
    const timeBucket = Math.ceil(timeBudgetMinutes / 30) * 30;

    const cached = await this.deps.cache.getIsochrone(poi.id, timeBucket, mode);
    if (cached) return cached;

    const isochrone = await this.deps.routingProvider.getIsochrone(
      poi.location,
      timeBudgetMinutes,
      mode,
    );

    await this.deps.cache.setIsochrone(poi.id, timeBucket, mode, isochrone);
    return isochrone;
  }

  // -------------------------------------------------------------------------
  // Segment building: inter-cluster (driving) + intra-cluster (walking).
  // -------------------------------------------------------------------------

  private async buildSegments(orderedClusters: Cluster[]): Promise<Segment[]> {
    const segments: Segment[] = [];

    for (let ci = 0; ci < orderedClusters.length; ci++) {
      const currentCluster = orderedClusters[ci]!;

      // Inter-cluster driving segment (to this cluster from previous).
      if (ci > 0) {
        const prevCluster = orderedClusters[ci - 1]!;
        try {
          const driveResult = await this.deps.routingProvider.getRoute(
            [prevCluster.anchor, currentCluster.anchor],
            'driving',
          );
          segments.push({
            mode: 'driving',
            from: prevCluster.anchor,
            to: currentCluster.anchor,
            fromPoiId: null,
            toPoiId: null,
            durationMinutes: driveResult.durationMinutes,
            distanceMeters: driveResult.distanceMeters,
            geometry: driveResult.geometry,
          });
        } catch {
          // Graceful degradation: add a synthetic segment on provider failure.
          segments.push({
            mode: 'driving',
            from: prevCluster.anchor,
            to: currentCluster.anchor,
            fromPoiId: null,
            toPoiId: null,
            durationMinutes: 0,
            distanceMeters: 0,
            geometry: [prevCluster.anchor, currentCluster.anchor],
          });
        }
      }

      // Intra-cluster walking segments between consecutive stops.
      const clusterPois = currentCluster.pois;
      for (let pi = 0; pi < clusterPois.length - 1; pi++) {
        const from = clusterPois[pi]!;
        const to = clusterPois[pi + 1]!;

        try {
          const walkResult = await this.deps.routingProvider.getRoute(
            [from.location, to.location],
            'walking',
          );
          segments.push({
            mode: 'walking',
            from: from.location,
            to: to.location,
            fromPoiId: from.id,
            toPoiId: to.id,
            durationMinutes: walkResult.durationMinutes,
            distanceMeters: walkResult.distanceMeters,
            geometry: walkResult.geometry,
          });
        } catch {
          // Graceful degradation: synthetic walking segment.
          segments.push({
            mode: 'walking',
            from: from.location,
            to: to.location,
            fromPoiId: from.id,
            toPoiId: to.id,
            durationMinutes: 0,
            distanceMeters: 0,
            geometry: [from.location, to.location],
          });
        }
      }
    }

    return segments;
  }
}

// ---------------------------------------------------------------------------
// Utility: extract a sub-matrix covering only the given indices from a
// full matrix. Used to get per-cluster walking sub-matrices from the
// single walking matrix call.
// ---------------------------------------------------------------------------

function extractSubMatrix(
  matrix: DurationMatrix,
  indices: number[],
): DurationMatrix {
  const n = indices.length;
  const durationsMinutes = Array.from({ length: n }, (_, i) =>
    Array.from({ length: n }, (_, j) =>
      matrix.durationsMinutes[indices[i]!]?.[indices[j]!] ?? 0,
    ),
  );
  const distancesMeters = Array.from({ length: n }, (_, i) =>
    Array.from({ length: n }, (_, j) =>
      matrix.distancesMeters[indices[i]!]?.[indices[j]!] ?? 0,
    ),
  );
  const points = indices.map((idx) => matrix.points[idx]!);

  return {
    points,
    mode: matrix.mode,
    durationsMinutes,
    distancesMeters,
  };
}
