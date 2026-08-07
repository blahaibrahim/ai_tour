/**
 * Location data access — Supabase-backed, with the curated set as a hard
 * fallback (docs/backend/12: "the curated 8 are the floor. Never show an empty
 * map."). Every function here degrades to `curatedLocations` on *any* failure
 * (network error, misconfiguration, empty/unexpected result) rather than
 * raising, because a stale-but-correct answer beats a 500 for a travel app.
 *
 * Callers (routes/*.ts) see one stable shape regardless of which source
 * answered:
 *     {id, name, region, category, blurb, task_type, task_label, lat, lng, distance_km}
 */
import { getLogger } from "../logger";
import { roundTo } from "../text";
import { unwrapRows } from "../supabase";
import { LocationDetail, LocationRow } from "../types";
import * as fallback from "./curatedLocations";
import { getClient, isConfigured } from "./supabaseClient";

const logger = getLogger("data.locationsRepo");

interface LocaleRow {
  locale: string;
  [key: string]: unknown;
}

interface NearbyRow {
  id: string;
  name: string;
  category: string;
  blurb: string;
  lat: number;
  lng: number;
  distance_km: number;
}

interface LocationExtras {
  id: string;
  photo_url?: string | null;
  regions?: { region_translations?: LocaleRow[] } | null;
  location_tasks?: Array<{
    type?: string;
    location_task_translations?: LocaleRow[];
  }> | null;
}

/**
 * From a list of {locale, ...} rows (a translations embed), pick the requested
 * locale, falling back to English, falling back to whatever's first. Mirrors
 * the SQL-side `coalesce(t.x, ten.x)` fallback in the `nearby_locations` RPC
 * (docs/backend/02) so single-row lookups behave the same way as the radius
 * query.
 */
function pickLocale(rows: LocaleRow[] | null | undefined, locale: string): LocaleRow | null {
  if (!rows || rows.length === 0) return null;
  const byLocale = new Map(rows.map((row) => [row.locale, row]));
  return byLocale.get(locale) ?? byLocale.get("en") ?? rows[0];
}

function firstTask(
  locationTasks: LocationExtras["location_tasks"],
  locale: string,
): [string | null, string | null] {
  if (!locationTasks || locationTasks.length === 0) return [null, null];
  const task = locationTasks[0];
  const labelRow = pickLocale(task.location_task_translations, locale);
  return [task.type ?? null, (labelRow?.label as string | undefined) ?? null];
}

function regionName(regions: LocationExtras["regions"], locale: string): string | null {
  if (!regions) return null;
  const nameRow = pickLocale(regions.region_translations, locale);
  return (nameRow?.name as string | undefined) ?? null;
}

export interface RadiusOptions {
  locale?: string;
  promptEmbedding?: number[] | null;
  categories?: string[] | null;
  limit?: number | null;
}

export async function locationsWithinRadius(
  lat: number,
  lng: number,
  radiusKm: number,
  options: RadiusOptions = {},
): Promise<LocationRow[]> {
  const { locale = "en", promptEmbedding = null, categories = null, limit = null } = options;

  if (!isConfigured()) {
    return fallback.locationsWithinRadius(lat, lng, radiusKm, limit);
  }

  try {
    const client = getClient();
    const rpcArgs: Record<string, unknown> = {
      p_lat: lat,
      p_lng: lng,
      p_radius_km: radiusKm,
      p_locale: locale,
    };
    if (promptEmbedding !== null && promptEmbedding !== undefined) {
      rpcArgs.p_prompt_embedding = promptEmbedding;
    }
    if (categories && categories.length > 0) {
      rpcArgs.p_categories = categories;
    }
    if (limit !== null && limit !== undefined) {
      rpcArgs.p_limit = limit;
    }

    let rpcRows = await unwrapRows<NearbyRow>(client.rpc("nearby_locations", rpcArgs));

    if (rpcRows.length === 0) {
      // Same "never an empty map" behaviour as the curated fallback:
      // widen the search rather than returning nothing.
      rpcRows = (
        await unwrapRows<NearbyRow>(
          client.rpc("nearby_locations", {
            p_lat: lat,
            p_lng: lng,
            p_radius_km: 20000,
            p_limit: 5,
            p_locale: locale,
          }),
        )
      ).sort((a, b) => a.distance_km - b.distance_km);
    }

    if (rpcRows.length === 0) {
      throw new Error("Supabase catalogue returned no locations at all");
    }

    const ids = rpcRows.map((r) => r.id);
    const extraRows = await unwrapRows<LocationExtras>(
      client
        .from("locations")
        .select(
          "id,photo_url," +
            "regions(region_translations(name,locale))," +
            "location_tasks(type,location_task_translations(label,locale))",
        )
        .in("id", ids),
    );
    const extraById = new Map(extraRows.map((row) => [row.id, row]));

    return rpcRows.map((r) => {
      const extra = extraById.get(r.id);
      const [taskType, taskLabel] = firstTask(extra?.location_tasks ?? [], locale);
      return {
        id: r.id,
        name: r.name,
        region: regionName(extra?.regions ?? null, locale),
        category: r.category,
        blurb: r.blurb,
        task_type: taskType,
        task_label: taskLabel,
        lat: r.lat,
        lng: r.lng,
        distance_km: roundTo(r.distance_km, 1),
        photo_url: extra?.photo_url ?? null,
      };
    });
  } catch (error) {
    logger.exception("Supabase locationsWithinRadius failed, falling back to curated set", error);
    return fallback.locationsWithinRadius(lat, lng, radiusKm);
  }
}

interface LocationDetailRow {
  id: string;
  category: string;
  location_translations?: LocaleRow[] | null;
  regions?: { region_translations?: LocaleRow[] } | null;
}

export async function getLocation(
  locationId: string,
  options: { locale?: string } = {},
): Promise<LocationDetail | null> {
  const { locale = "en" } = options;

  if (!isConfigured()) {
    return fallback.getLocation(locationId);
  }

  try {
    const client = getClient();
    const rows = await unwrapRows<LocationDetailRow>(
      client
        .from("locations")
        .select(
          "id,category," +
            "location_translations(name,blurb,locale)," +
            "regions(region_translations(name,locale))",
        )
        .eq("id", locationId)
        .eq("is_active", true)
        .limit(1),
    );

    if (rows.length === 0) {
      // A miss is a real answer (unknown id), not a failure — don't
      // mask it by falling back to a curated id that happens to exist.
      return null;
    }

    const row = rows[0];
    const translation = pickLocale(row.location_translations, locale);
    if (translation === null) {
      return null;
    }

    return {
      id: row.id,
      name: translation.name as string,
      region: regionName(row.regions ?? null, locale),
      category: row.category,
      blurb: translation.blurb as string,
    };
  } catch (error) {
    logger.exception("Supabase getLocation failed, falling back to curated set", error);
    return fallback.getLocation(locationId);
  }
}
