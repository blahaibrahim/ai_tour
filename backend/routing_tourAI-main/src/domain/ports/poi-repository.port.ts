import type { Poi } from '../models/poi.model.js';

export interface PoiQuery {
  cityId: string;
  /**
   * Matches against category key / theme grouping. Which categories map
   * to which theme is a business rule owned by POI Selector (Domain),
   * not by this repository — this field just carries the filter through.
   */
  theme?: string;
  categoryIds?: string[];
}

/**
 * PostGIS-backed access to the `pois` table (Section 3/7). Implementations
 * return only `status = 'published'` rows — draft and api_seeded POIs
 * (Section 10) are never eligible for route generation, filtered at the
 * query level so Domain never has to remember to check status itself.
 */
export interface PoiRepository {
  findEligible(query: PoiQuery): Promise<Poi[]>;
  findById(id: string): Promise<Poi | null>;
}
