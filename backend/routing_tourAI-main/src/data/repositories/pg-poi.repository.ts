import type { Kysely } from 'kysely';
import { sql } from 'kysely';
import type { DB } from '../db/types.js';
import type { PoiRepository, PoiQuery } from '../../domain/ports/poi-repository.port.js';
import type { Poi } from '../../domain/models/poi.model.js';

export class PgPoiRepository implements PoiRepository {
  constructor(private readonly db: Kysely<DB>) {}

  async findEligible(filter: PoiQuery): Promise<Poi[]> {
    let query = this.db
      .selectFrom('pois')
      .select([
        'id',
        'city_id',
        'category_id',
        'name_fr',
        'name_ar',
        'name_en',
        'description_fr',
        'description_ar',
        'description_en',
        sql<number>`ST_Y(location::geometry)`.as('lat'),
        sql<number>`ST_X(location::geometry)`.as('lng'),
        'opening_hours_raw',
        'avg_visit_duration_minutes',
        'checkpoint_radius_meters',
      ])
      .where('status', '=', 'published')
      .where('deleted_at', 'is', null);

    if (filter.cityId) {
      query = query.where('city_id', '=', filter.cityId);
    }
    if (filter.categoryIds && filter.categoryIds.length > 0) {
      query = query.where('category_id', 'in', filter.categoryIds);
    }

    const rows = await query.execute();

    return rows.map((row) => ({
      id: row.id,
      cityId: row.city_id,
      categoryId: row.category_id,
      nameFr: row.name_fr ?? null,
      nameAr: row.name_ar ?? null,
      nameEn: row.name_en ?? null,
      location: {
        lat: row.lat,
        lng: row.lng,
      },
      openingHoursRaw: row.opening_hours_raw ?? null,
      avgVisitDurationMinutes: row.avg_visit_duration_minutes,
      checkpointRadiusMeters: row.checkpoint_radius_meters,
    }));
  }

  async findById(id: string): Promise<Poi | null> {
    const row = await this.db
      .selectFrom('pois')
      .select([
        'id',
        'city_id',
        'category_id',
        'name_fr',
        'name_ar',
        'name_en',
        'description_fr',
        'description_ar',
        'description_en',
        sql<number>`ST_Y(location::geometry)`.as('lat'),
        sql<number>`ST_X(location::geometry)`.as('lng'),
        'opening_hours_raw',
        'avg_visit_duration_minutes',
        'checkpoint_radius_meters',
      ])
      .where('id', '=', id)
      .where('deleted_at', 'is', null)
      .executeTakeFirst();

    if (!row) return null;

    return {
      id: row.id,
      cityId: row.city_id,
      categoryId: row.category_id,
      nameFr: row.name_fr ?? null,
      nameAr: row.name_ar ?? null,
      nameEn: row.name_en ?? null,
      location: { lat: row.lat, lng: row.lng },
      openingHoursRaw: row.opening_hours_raw ?? null,
      avgVisitDurationMinutes: row.avg_visit_duration_minutes,
      checkpointRadiusMeters: row.checkpoint_radius_meters,
    };
  }
}
