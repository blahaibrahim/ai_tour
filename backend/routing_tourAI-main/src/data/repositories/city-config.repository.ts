import type { CityConfig } from '../../domain/models/city-config.model.js';
import type { CityConfigRepository } from '../../domain/ports/city-config-repository.port.js';

/**
 * In-memory CityConfigRepository backed by a pre-loaded list of configs
 * (Section 3: "Cached in memory with a short refresh interval"). In the
 * real Data layer this would query the `cities` table and cache rows
 * with a TTL — here the fixture list itself is the cache.
 */
export class InMemoryCityConfigRepository implements CityConfigRepository {
  private readonly configs: CityConfig[];

  constructor(configs: CityConfig[]) {
    this.configs = configs;
  }

  async findById(cityId: string): Promise<CityConfig | null> {
    return this.configs.find((c) => c.id === cityId) ?? null;
  }

  async findByName(name: string): Promise<CityConfig | null> {
    const lower = name.toLowerCase();
    return (
      this.configs.find(
        (c) =>
          c.name.toLowerCase() === lower ||
          c.nameFr?.toLowerCase() === lower ||
          c.nameAr === name,
      ) ?? null
    );
  }
}
