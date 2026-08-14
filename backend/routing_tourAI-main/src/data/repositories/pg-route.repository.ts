import type { Kysely } from 'kysely';
import { sql } from 'kysely';
import type { DB } from '../db/types.js';
import type { RouteRepository } from '../../domain/ports/route-repository.port.js';
import type { PersistedRoute, RouteResponse, Waypoint } from '../../domain/models/route.model.js';
import type { Segment } from '../../domain/models/segment.model.js';

export class PgRouteRepository implements RouteRepository {
  constructor(private readonly db: Kysely<DB>) {}

  async save(
    route: RouteResponse,
    context: { sessionId?: string; userId?: string },
  ): Promise<PersistedRoute> {
    return this.db.transaction().execute(async (trx) => {
      // 1. Insert the route
      const insertedRoute = await trx
        .insertInto('routes')
        .values({
          city_id: route.cityId,
          session_id: context.sessionId ?? null,
          user_id: context.userId ?? null,
          theme: route.theme,
          time_budget_minutes: route.timeBudgetMinutes,
          transport_mode: route.transportMode,
          segments: JSON.stringify(route.segments),
          estimated_total_duration_minutes: route.estimatedTotalDurationMinutes,
          day_count_flag: route.dayCountFlag,
        })
        .returning(['id', 'generated_at'])
        .executeTakeFirstOrThrow();

      // 2. Insert the waypoints into route_stops
      if (route.waypoints.length > 0) {
        await trx
          .insertInto('route_stops')
          .values(
            route.waypoints.map((wp) => ({
              route_id: insertedRoute.id,
              poi_id: wp.poiId,
              sequence_order: wp.sequenceOrder,
              cluster_id: wp.clusterId,
            })),
          )
          .execute();
      }

      return {
        id: insertedRoute.id,
        sessionId: context.sessionId ?? null,
        userId: context.userId ?? null,
        generatedAt: insertedRoute.generated_at,
        ...route,
      };
    });
  }

  async findById(id: string): Promise<PersistedRoute | null> {
    const routeRow = await this.db
      .selectFrom('routes')
      .selectAll()
      .where('id', '=', id)
      .executeTakeFirst();

    if (!routeRow) return null;

    // Fetch waypoints joining with pois to get coordinates and checkpoint_radius
    const stops = await this.db
      .selectFrom('route_stops as rs')
      .innerJoin('pois as p', 'p.id', 'rs.poi_id')
      .select([
        'rs.poi_id',
        'rs.sequence_order',
        'rs.cluster_id',
        sql<number>`ST_Y(p.location::geometry)`.as('lat'),
        sql<number>`ST_X(p.location::geometry)`.as('lng'),
        'p.checkpoint_radius_meters',
      ])
      .where('rs.route_id', '=', id)
      .orderBy('rs.sequence_order', 'asc')
      .execute();

    const waypoints: Waypoint[] = stops.map((s) => ({
      poiId: s.poi_id,
      sequenceOrder: s.sequence_order,
      clusterId: s.cluster_id,
      location: { lat: s.lat, lng: s.lng },
      checkpointRadiusMeters: s.checkpoint_radius_meters,
    }));

    return {
      id: routeRow.id,
      sessionId: routeRow.session_id,
      userId: routeRow.user_id,
      generatedAt: routeRow.generated_at,
      cityId: routeRow.city_id,
      theme: routeRow.theme,
      timeBudgetMinutes: routeRow.time_budget_minutes,
      transportMode: routeRow.transport_mode,
      segments: routeRow.segments as Segment[],
      waypoints,
      estimatedTotalDurationMinutes: routeRow.estimated_total_duration_minutes,
      dayCountFlag: routeRow.day_count_flag,
    };
  }
}
