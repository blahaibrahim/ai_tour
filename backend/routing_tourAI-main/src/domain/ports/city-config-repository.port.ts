import type { CityConfig } from '../models/city-config.model.js';

/**
 * Per-city settings access (Section 3/7). Implementations are expected
 * to cache in memory with a short refresh interval — that caching detail
 * lives in the Data layer implementation, not in this contract.
 */
export interface CityConfigRepository {
  findById(cityId: string): Promise<CityConfig | null>;
  findByName(name: string): Promise<CityConfig | null>;
}
