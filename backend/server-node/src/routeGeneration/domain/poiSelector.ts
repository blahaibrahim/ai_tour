/**
 * Layer 3 — POI Selector.
 *
 * Queries eligible, published POIs by theme, opening hours and city (spec §3).
 * The first stage of the pipeline and the one that decides what the route can
 * possibly contain.
 *
 * STATUS: stub. Needs the Data layer (spec §9 step 4).
 *
 * Eligibility, in full:
 *   • `city_id` matches, `status = 'published'`, `deleted_at IS NULL`.
 *   • Category is in the requested theme's category set.
 *   • The POI is open. `opening_hours_raw` holds OSM opening_hours syntax
 *     specifically so this is parseable rather than guessed (spec §10).
 *
 * The theme-to-categories mapping has no home in the spec's schema — `routes`
 * stores a `theme` string and `pois` carry a `category_id`, with nothing
 * joining them. Whoever implements this needs to decide where it lives; a
 * `theme` column on `categories`, or a join table, are both cheaper than
 * hardcoding the mapping here where a new city cannot change it without a
 * deploy (which would break the "config, not code changes" property in §2).
 */
import { NotImplementedError } from "../errors";
import { Locale, Poi } from "../types";

export interface SelectPoisInput {
  cityId: string;
  theme: string;
  categoryKeys?: string[];
  /** Evaluated against `opening_hours_raw`; omit to skip the hours filter. */
  now?: Date;
  locale?: Locale;
}

export function selectPois(_input: SelectPoisInput): Promise<Poi[]> {
  throw new NotImplementedError("POISelector.selectPois");
}

/**
 * Resolves a theme name to the category keys it covers.
 *
 * Separate from `selectPois` because it is the piece with an unresolved home
 * (see the module docstring) — keeping it behind its own function means
 * moving it into the database later touches one body, not the query.
 */
export function categoriesForTheme(_cityId: string, _theme: string): Promise<string[]> {
  throw new NotImplementedError("POISelector.categoriesForTheme");
}
