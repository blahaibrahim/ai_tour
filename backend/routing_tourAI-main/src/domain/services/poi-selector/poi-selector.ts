import type { Poi } from '../../models/poi.model.js';
import type { PoiRepository } from '../../ports/poi-repository.port.js';

/**
 * POI Selector (Section 3): queries eligible, published POIs by theme,
 * opening hours, and city. Delegates the DB query to PoiRepository and
 * applies the theme-to-category mapping that is a business rule owned
 * here in Domain, not in the Data layer.
 */
export class PoiSelector {
  private readonly poiRepository: PoiRepository;
  private readonly themeCategoryMap: Record<string, string[]>;

  constructor(
    poiRepository: PoiRepository,
    themeCategoryMap: Record<string, string[]>,
  ) {
    this.poiRepository = poiRepository;
    this.themeCategoryMap = themeCategoryMap;
  }

  /**
   * Returns published POIs in the given city that belong to the
   * categories mapped to `theme`. If the theme is unknown or maps to no
   * categories, returns an empty array — the caller (Orchestrator)
   * decides whether that's an error.
   */
  async select(cityId: string, theme: string): Promise<Poi[]> {
    const categoryIds = this.themeCategoryMap[theme];
    if (!categoryIds || categoryIds.length === 0) return [];

    const pois = await this.poiRepository.findEligible({ cityId, categoryIds });
    return pois;
  }
}
