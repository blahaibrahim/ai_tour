/**
 * Layer 5 — POI Repository. PostGIS spatial, status and category queries.
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
 *
 * ## Why every read goes through an RPC
 *
 * `pois.location` is `geography(POINT,4326)`. PostgREST hands a geography
 * column back as hex EWKB (`0101000020E6100000…`), not coordinates, and it has
 * no way to express `ST_Y(location::geometry)` in a `select()`. The reference
 * implementation this module is a port of used raw SQL through Kysely, which
 * is not available here.
 *
 * So the projection lives in `public.pois_eligible` and
 * `public.route_stops_expanded` (migration 20260814101215), which return
 * `lat`/`lng` as doubles and join `categories` for the key. Same shape as the
 * existing `nearby_locations` RPC — this is the established pattern in this
 * codebase for anything spatial, not a new one invented here.
 */
import type { SupabaseClient } from "@supabase/supabase-js";

import { getClient } from "../../data/supabaseClient";
import { unwrap } from "../../supabase";
import { Category, Coordinate, Poi, PoiSource, PoiStatus } from "../types";

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

export interface AvailableCategory {
  key: string;
  labelEn: string;
  labelFr: string;
  labelAr: string;
  /** How many published POIs in this city (and theme, when narrowed) carry
   * this category — the LLM prompt interpreter's tie-breaker between two
   * otherwise-plausible readings of the same sentence. */
  poiCount: number;
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
  /** Categories with at least one published POI in `cityId`, optionally
   * narrowed to one theme's own set (see `categories_available`, migration
   * 20260818130000). This is the vocabulary the LLM prompt interpreter is
   * constrained to — mirrors why `themes_available` exists for themes: a
   * category with nothing behind it here is a category worth never
   * returning, LLM or chip picker alike. */
  listAvailableCategories(cityId: string, themeKey?: string): Promise<AvailableCategory[]>;
}

/** One row as `public.pois_eligible` returns it. */
interface PoiRow {
  id: string;
  city_id: string;
  category_id: string;
  category_key: string;
  name_en: string | null;
  name_fr: string | null;
  name_ar: string | null;
  description_en: string | null;
  description_fr: string | null;
  description_ar: string | null;
  lat: number;
  lng: number;
  opening_hours_raw: string | null;
  avg_visit_duration_minutes: number;
  checkpoint_radius_meters: number;
  ar_content_id: string | null;
  stamp_id: string | null;
  external_ref: string | null;
  source: string;
  status: string;
  photo_url: string | null;
  photo_attribution: string | null;
  photo_license: string | null;
  photo_source_url: string | null;
  interest_score: number | string | null;
}

export function rowToPoi(row: PoiRow): Poi {
  return {
    id: row.id,
    cityId: row.city_id,
    categoryId: row.category_id,
    categoryKey: row.category_key,
    nameEn: row.name_en,
    nameFr: row.name_fr,
    nameAr: row.name_ar,
    descriptionEn: row.description_en,
    descriptionFr: row.description_fr,
    descriptionAr: row.description_ar,
    // The RPC returns lat/lng already projected out of the geography column;
    // the [lng, lat] ordering PostGIS and GeoJSON use never reaches Domain.
    location: { lat: row.lat, lng: row.lng },
    openingHoursRaw: row.opening_hours_raw,
    avgVisitDurationMinutes: row.avg_visit_duration_minutes,
    checkpointRadiusMeters: row.checkpoint_radius_meters,
    arContentId: row.ar_content_id,
    stampId: row.stamp_id,
    externalRef: row.external_ref,
    source: row.source as PoiSource,
    status: row.status as PoiStatus,
    photoUrl: row.photo_url,
    photoAttribution: row.photo_attribution,
    photoLicense: row.photo_license,
    photoSourceUrl: row.photo_source_url,
    // numeric comes back as a string over PostgREST.
    interestScore: row.interest_score === null || row.interest_score === undefined
      ? null
      : Number(row.interest_score),
  };
}

class SupabasePoiRepository implements PoiRepository {
  private get db(): SupabaseClient {
    return getClient();
  }

  async findEligible(query: SelectPoisQuery): Promise<Poi[]> {
    const rows =
      (await unwrap<PoiRow[]>(
        this.db.rpc("pois_eligible", {
          p_city_id: query.cityId,
          // null, not [] — the RPC reads an empty array as "match nothing",
          // while the contract here says "no filter means every category".
          p_category_keys:
            query.categoryKeys && query.categoryKeys.length > 0 ? query.categoryKeys : null,
          p_limit: query.limit ?? 200,
        }),
      )) ?? [];

    const pois = rows.map(rowToPoi);
    // The hours filter is applied here rather than in SQL: Postgres has no OSM
    // opening_hours parser, and pushing a half-correct approximation into the
    // query would silently drop POIs no one could see was being dropped.
    return query.openAt ? pois.filter((p) => isOpenAt(p.openingHoursRaw, query.openAt!)) : pois;
  }

  async findByIds(ids: string[]): Promise<Poi[]> {
    if (ids.length === 0) return [];
    // pois_eligible is scoped to a city by design; this is the one read that
    // is not, so it goes through the table and re-projects the coordinates
    // from the columns PostgREST can return.
    const rows =
      (await unwrap<Array<Record<string, unknown>>>(
        this.db
          .from("pois")
          .select(
            "id, city_id, category_id, name_en, name_fr, name_ar, " +
              "description_en, description_fr, description_ar, opening_hours_raw, " +
              "avg_visit_duration_minutes, checkpoint_radius_meters, ar_content_id, " +
              "stamp_id, external_ref, source, status, photo_url, photo_attribution, " +
              "photo_license, photo_source_url, interest_score, categories(key)",
          )
          .in("id", ids)
          .is("deleted_at", null),
      )) ?? [];

    // No lat/lng here — the geography column cannot come back as coordinates
    // over PostgREST, so callers that need positions use findEligible. This
    // exists for the refine path, which only needs to know which ids exist.
    return rows.map((r) =>
      rowToPoi({
        ...(r as unknown as PoiRow),
        category_key: ((r.categories as { key?: string } | null)?.key ?? "") as string,
        lat: Number.NaN,
        lng: Number.NaN,
      }),
    );
  }

  async findAllPublished(cityId: string): Promise<Poi[]> {
    // The warm job wants the whole city, which is also the matrix the
    // orchestrator caches — 500 is the RPC's own ceiling.
    return this.findEligible({ cityId, limit: 500 });
  }

  async findWithinRadius(
    centre: Coordinate,
    radiusMeters: number,
    cityId: string,
  ): Promise<Poi[]> {
    // Filtered in memory rather than with ST_DWithin: the GIST index only pays
    // for itself at catalogue scale, and a city's published set is in the tens.
    // When that stops being true this becomes its own RPC, not a bigger query.
    const pois = await this.findAllPublished(cityId);
    return pois.filter((p) => haversineMeters(centre, p.location) <= radiusMeters);
  }

  async listCategories(): Promise<Category[]> {
    const rows =
      (await unwrap<
        Array<{
          id: string;
          key: string;
          label_en: string;
          label_fr: string;
          label_ar: string;
          icon_ref: string | null;
          color_hex: string | null;
        }>
      >(
        this.db
          .from("categories")
          .select("id, key, label_en, label_fr, label_ar, icon_ref, color_hex")
          .order("key"),
      )) ?? [];

    return rows.map((r) => ({
      id: r.id,
      key: r.key,
      labelEn: r.label_en,
      labelFr: r.label_fr,
      labelAr: r.label_ar,
      iconRef: r.icon_ref,
      colorHex: r.color_hex,
    }));
  }

  async listAvailableCategories(cityId: string, themeKey?: string): Promise<AvailableCategory[]> {
    const rows =
      (await unwrap<
        Array<{
          key: string;
          label_en: string;
          label_fr: string;
          label_ar: string;
          poi_count: number | string;
        }>
      >(
        this.db.rpc("categories_available", {
          p_city_id: cityId,
          p_theme_key: themeKey ?? null,
        }),
      )) ?? [];

    return rows.map((r) => ({
      key: r.key,
      labelEn: r.label_en,
      labelFr: r.label_fr,
      labelAr: r.label_ar,
      // bigint comes back as a string over PostgREST.
      poiCount: Number(r.poi_count),
    }));
  }
}

// ---------------------------------------------------------------------------
// OSM opening_hours — the subset the seeded catalogue actually uses.
// ---------------------------------------------------------------------------

const DAY_INDEX: Record<string, number> = {
  su: 0, mo: 1, tu: 2, we: 3, th: 4, fr: 5, sa: 6,
};

/**
 * Evaluates `opening_hours_raw` against a moment.
 *
 * Handles the grammar the catalogue uses — `Mo-Su 08:00-18:00`,
 * `Tu-Su 10:00-17:00`, `24/7`, and semicolon-separated rules — and
 * **fails open** on anything it does not understand.
 *
 * Failing open is the deliberate choice: this is a filter on what a traveller
 * is shown, and wrongly excluding an open landmark is invisible (the route is
 * simply poorer), while wrongly including a closed one is at least visible and
 * recoverable when they get there. A parser that silently emptied routes on
 * syntax it had not met would be the worse failure, and it would look like
 * "there is nothing in this city".
 *
 * The full grammar (public holidays, `sunset`, month ranges, `off`) is a
 * library-sized problem. If the catalogue starts carrying it, reach for
 * `opening_hours.js` rather than growing this.
 */
export function isOpenAt(raw: string | null, at: Date): boolean {
  if (!raw) return true; // No hours recorded is not evidence of being shut.

  const spec = raw.trim();
  if (!spec || /24\s*\/\s*7/i.test(spec)) return true;

  const day = at.getDay();
  const minutes = at.getHours() * 60 + at.getMinutes();

  let sawUsableRule = false;

  for (const rule of spec.split(";")) {
    const match = rule
      .trim()
      .match(/^([A-Za-z]{2}(?:\s*-\s*[A-Za-z]{2})?)\s+(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})$/);
    if (!match) continue;

    const [, dayPart, fromH, fromM, toH, toM] = match;
    const days = expandDayRange(dayPart!);
    if (days === null) continue;

    sawUsableRule = true;
    if (!days.has(day)) continue;

    const from = Number(fromH) * 60 + Number(fromM);
    let to = Number(toH) * 60 + Number(toM);
    // A closing time at or before opening crosses midnight (`20:00-02:00`).
    if (to <= from) to += 24 * 60;

    if (minutes >= from && minutes <= to) return true;
    if (minutes + 24 * 60 >= from && minutes + 24 * 60 <= to) return true;
  }

  // Every rule was unparseable — treat the whole value as unknown, not as
  // "closed", per the fail-open rule above.
  return !sawUsableRule;
}

function expandDayRange(part: string): Set<number> | null {
  const bounds = part.split("-").map((d) => DAY_INDEX[d.trim().toLowerCase().slice(0, 2)]);
  if (bounds.some((b) => b === undefined)) return null;

  const [start, end] = [bounds[0]!, bounds.length > 1 ? bounds[1]! : bounds[0]!];
  const days = new Set<number>();
  // Wraps: `Sa-Su` and `Fr-Mo` are both legal and both cross the week boundary.
  for (let i = start; ; i = (i + 1) % 7) {
    days.add(i);
    if (i === end) break;
  }
  return days;
}

/** Great-circle metres. Duplicated from the clustering engine on purpose —
 * Layer 5 importing Layer 3 would invert the dependency direction. */
function haversineMeters(a: Coordinate, b: Coordinate): number {
  const R = 6_371_000;
  const toRad = (deg: number): number => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

let shared: PoiRepository | null = null;

export function getPoiRepository(): PoiRepository {
  if (shared === null) shared = new SupabasePoiRepository();
  return shared;
}
