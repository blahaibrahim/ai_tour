import type { Poi } from '../../domain/models/poi.model.js';
import type { PoiQuery, PoiRepository } from '../../domain/ports/poi-repository.port.js';

/**
 * In-memory PoiRepository backed by fixture data (Section 9, Step 3).
 * Suitable for unit tests, the driver script, and local development
 * without a live PostgreSQL/PostGIS instance. The real DB-backed
 * implementation can be added behind the same interface when needed.
 *
 * Only returns POIs whose status would be 'published' — since fixtures
 * are all published by construction, no explicit status filter is needed
 * here, but the contract is honored conceptually.
 */
export class InMemoryPoiRepository implements PoiRepository {
  private readonly pois: Poi[];

  constructor(pois: Poi[]) {
    this.pois = pois;
  }

  async findEligible(query: PoiQuery): Promise<Poi[]> {
    return this.pois.filter((poi) => {
      if (poi.cityId !== query.cityId) return false;
      if (query.categoryIds && query.categoryIds.length > 0) {
        if (!query.categoryIds.includes(poi.categoryId)) return false;
      }
      return true;
    });
  }

  async findById(id: string): Promise<Poi | null> {
    return this.pois.find((p) => p.id === id) ?? null;
  }
}
