/**
 * Layer 3 — POI Selector.
 *
 * Queries eligible, published POIs by theme, opening hours and city (spec §3).
 * The first stage of the pipeline and the one that decides what the route can
 * possibly contain.
 *
 * Eligibility, in full:
 *   • `city_id` matches, `status = 'published'`, `deleted_at IS NULL`.
 *   • Category is in the requested theme's category set.
 *   • The POI is open. `opening_hours_raw` holds OSM opening_hours syntax
 *     specifically so this is parseable rather than guessed (spec §10).
 *
 * ## Where the theme→category mapping lives
 *
 * In the database, as `themes` + `theme_categories` (migration
 * 20260814102500) — resolved through the `theme_category_keys` RPC below.
 *
 * The alternative was a constant in this file, which is what the reference
 * implementation does. It was rejected for the reason the module docstring
 * originally flagged: a hardcoded map is the same in every city and changing
 * it needs a deploy, which breaks the "config, not code changes" property
 * (spec §2) that `cities.cluster_radius_meters`, `active_routing_provider`
 * and `rollout_status` all exist to provide. "Nature" means beaches and
 * coastal parks in Algiers and desert and oases in Tamanrasset; that is a row,
 * not a release.
 *
 * It is also the vocabulary the LLM prompt interpreter is constrained to, so
 * the theme chips and the model read one list and cannot drift apart.
 */
import { getPoiRepository } from "../data/poiRepository";
import { getClient } from "../../data/supabaseClient";
import { unwrap } from "../../supabase";
import { Locale, Poi } from "../types";

export interface SelectPoisInput {
  cityId: string;
  theme: string;
  categoryKeys?: string[];
  /** Evaluated against `opening_hours_raw`; omit to skip the hours filter. */
  now?: Date;
  locale?: Locale;
}

export async function selectPois(input: SelectPoisInput): Promise<Poi[]> {
  const themeCategories = await categoriesForTheme(input.cityId, input.theme);

  // An explicit category filter narrows *within* the theme rather than
  // replacing it — "museums, in a history route" is one request, and letting
  // the narrower list win outright would silently turn it into two.
  //
  // An intersection that comes back empty means the traveller narrowed to
  // something the theme does not contain. Falling back to the theme would
  // quietly ignore what they asked for, so the empty set stands and the
  // orchestrator raises NoEligiblePoisError.
  const categoryKeys =
    input.categoryKeys && input.categoryKeys.length > 0
      ? input.categoryKeys.filter((k) => themeCategories.includes(k))
      : themeCategories;

  if (categoryKeys.length === 0) return [];

  return getPoiRepository().findEligible({
    cityId: input.cityId,
    categoryKeys,
    openAt: input.now,
  });
}

/**
 * Resolves a theme name to the category keys it covers.
 *
 * Kept behind its own function, as the original stub asked, so that where the
 * mapping lives stays a one-body change. The override rule — a city's own rows
 * replace the global set rather than adding to it — is inside the RPC, so it
 * cannot be reimplemented differently by another caller.
 */
export async function categoriesForTheme(cityId: string, theme: string): Promise<string[]> {
  const rows =
    (await unwrap<Array<{ category_key: string }>>(
      getClient().rpc("theme_category_keys", { p_theme_key: theme, p_city_id: cityId }),
    )) ?? [];
  return rows.map((r) => r.category_key);
}
