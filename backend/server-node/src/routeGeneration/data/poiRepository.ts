/**
 * Layer 5 — POI Repository. PostGIS spatial, status and category queries.
 *
 * STATUS: stubs. Build with 5–10 hand-authored fixture POIs and test the query
 * methods directly against them (spec §9 step 3, §11).
 *
 * Two rules the implementation must not lose:
 *   • Only `status = 'published'` POIs are ever eligible for a route. Overpass
 *     lands rows as `api_seeded` + `draft`; they are reviewed before publishing
 *     (spec §10). The RLS policy in sql/001 enforces this too, but the query
 *     should state it rather than rely on the policy.
 *   • `deleted_at IS NULL`. Soft deletes are the only kind here.
 *
 * The index that makes these cheap already exists:
 *   idx_pois_city_status_category (city_id, status, category_id)
 */
import { NotImplementedError } from "../errors";
import { Category, Coordinate, Poi } from "../types";

export interface SelectPoisQuery {
  cityId: string;
  /** Category keys to include. Empty/undefined means every published POI. */
  categoryKeys?: string[];
  /**
   * When supplied, POIs whose `opening_hours_raw` says they are shut at this
   * moment are excluded. Parsed with the OSM opening_hours grammar — the field
   * is stored parseable precisely so this is a query concern, not free-text
   * guesswork (spec §10).
   */
  openAt?: Date;
  limit?: number;
}

export interface PoiRepository {
  findEligible(query: SelectPoisQuery): Promise<Poi[]>;
  findByIds(ids: string[]): Promise<Poi[]>;
  /** For the nightly warm job: every published POI in a city, for the matrix. */
  findAllPublished(cityId: string): Promise<Poi[]>;
  /** Spatial. Not needed by the generation pipeline, but the AR trigger service
   * and the map screen both want it, and the GIST index is already there. */
  findWithinRadius(centre: Coordinate, radiusMeters: number, cityId: string): Promise<Poi[]>;
  listCategories(): Promise<Category[]>;
}

class SupabasePoiRepository implements PoiRepository {
  findEligible(_query: SelectPoisQuery): Promise<Poi[]> {
    throw new NotImplementedError("PoiRepository.findEligible");
  }
  findByIds(_ids: string[]): Promise<Poi[]> {
    throw new NotImplementedError("PoiRepository.findByIds");
  }
  findAllPublished(_cityId: string): Promise<Poi[]> {
    throw new NotImplementedError("PoiRepository.findAllPublished");
  }
  findWithinRadius(
    _centre: Coordinate,
    _radiusMeters: number,
    _cityId: string,
  ): Promise<Poi[]> {
    throw new NotImplementedError("PoiRepository.findWithinRadius");
  }
  listCategories(): Promise<Category[]> {
    throw new NotImplementedError("PoiRepository.listCategories");
  }
}

let shared: PoiRepository | null = null;

export function getPoiRepository(): PoiRepository {
  if (shared === null) shared = new SupabasePoiRepository();
  return shared;
}
