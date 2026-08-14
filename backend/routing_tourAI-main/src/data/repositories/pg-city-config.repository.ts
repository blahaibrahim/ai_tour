import type { Kysely } from 'kysely';
import type { DB, CityRow } from '../db/types.js';
import type { CityConfigRepository } from '../../domain/ports/city-config-repository.port.js';
import type { CityConfig } from '../../domain/models/city-config.model.js';

export class PgCityConfigRepository implements CityConfigRepository {
  constructor(private readonly db: Kysely<DB>) {}

  private mapRowToModel(row: CityRow): CityConfig {
    return {
      id: row.id,
      name: row.name,
      nameAr: row.name_ar ?? null,
      nameFr: row.name_fr ?? null,
      clusterRadiusMeters: row.cluster_radius_meters,
      activeRoutingProvider: row.active_routing_provider,
      rolloutStatus: row.rollout_status,
      featureFlags: row.feature_flags as Record<string, unknown>,
    };
  }

  async findByName(name: string): Promise<CityConfig | null> {
    const row = await this.db
      .selectFrom('cities')
      .selectAll()
      .where('name', '=', name)
      .where('deleted_at', 'is', null)
      .executeTakeFirst();
    return row ? this.mapRowToModel(row) : null;
  }

  async findById(id: string): Promise<CityConfig | null> {
    const row = await this.db
      .selectFrom('cities')
      .selectAll()
      .where('id', '=', id)
      .where('deleted_at', 'is', null)
      .executeTakeFirst();
    return row ? this.mapRowToModel(row) : null;
  }
}
