/**
 * Layer 5 — AR Content Repository. Per-POI AR configuration and spawn-zone
 * polygons (plan §3, §7). PostGIS.
 *
 * The `spawn_zone` column is a GEOGRAPHY(POLYGON, 4326). supabase-js returns
 * geography columns as WKB hex strings, so we ask PostGIS for GeoJSON via
 * ST_AsGeoJSON in the select and parse the coordinates ring out of it.
 * On insert/update we convert back via ST_GeomFromGeoJSON.
 *
 * STATUS: implemented.
 */
import { getAdminClient } from "../../ingestion/supabaseAdmin";
import { getClient } from "../../data/supabaseClient";
import { unwrap } from "../../supabase";
import { ArContent } from "../types";

export interface ArContentRepository {
  findByPoiId(poiId: string): Promise<ArContent | null>;
  findById(id: string): Promise<ArContent | null>;
  /** For the admin spawn-zone editor / isochrone proposal job (plan §9 step 10). */
  upsertSpawnZone(
    poiId: string,
    zone: ArContent["spawnZone"],
    reviewedBy: string,
  ): Promise<ArContent>;
}

/** Select list that converts the geography column to GeoJSON on the way out. */
const SELECT_WITH_GEO =
  "id, poi_id, mascot_id, ST_AsGeoJSON(spawn_zone)::jsonb as spawn_zone, " +
  "spawn_radius_meters, capture_radius_meters, hot_radius_meters, " +
  "band_thresholds, presentation_distance_meters, is_enabled, " +
  "zone_reviewed_by, zone_reviewed_at";

/** Parses the GeoJSON polygon's coordinate rings.
 *  GeoJSON Polygon: { type: "Polygon", coordinates: [[ [lng,lat], ... ]] }
 *  ArContent.spawnZone: Array<Array<[number, number]>>  ([lng, lat] pairs)
 */
function parseSpawnZone(raw: unknown): Array<Array<[number, number]>> {
  try {
    const gj = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (gj && typeof gj === "object" && Array.isArray((gj as { coordinates?: unknown }).coordinates)) {
      return (gj as { coordinates: Array<Array<[number, number]>> }).coordinates;
    }
  } catch {
    // fall through
  }
  return [];
}

function rowToArContent(row: Record<string, unknown>): ArContent {
  const thresholds = (row.band_thresholds as Record<string, number>) ?? {};
  return {
    id: row.id as string,
    poiId: row.poi_id as string,
    mascotId: row.mascot_id as string,
    spawnZone: parseSpawnZone(row.spawn_zone),
    spawnRadiusMeters: row.spawn_radius_meters as number,
    captureRadiusMeters: row.capture_radius_meters as number,
    hotRadiusMeters: row.hot_radius_meters as number,
    bandThresholds: {
      coldMeters: thresholds.cold_meters,
      warmMeters: thresholds.warm_meters,
      hotMeters: thresholds.hot_meters,
      burningMeters: thresholds.burning_meters,
    },
    presentationDistanceMeters: Number(row.presentation_distance_meters),
    isEnabled: row.is_enabled as boolean,
    zoneReviewedBy: (row.zone_reviewed_by as string | null) ?? null,
  };
}

/** Serialises the zone ring array back to a GeoJSON polygon string for PostGIS. */
function zoneToGeoJson(zone: Array<Array<[number, number]>>): string {
  return JSON.stringify({ type: "Polygon", coordinates: zone });
}

class SupabaseArContentRepository implements ArContentRepository {
  async findByPoiId(poiId: string): Promise<ArContent | null> {
    const row = await unwrap<Record<string, unknown>>(
      getClient()
        .from("ar_contents")
        .select(SELECT_WITH_GEO)
        .eq("poi_id", poiId)
        .eq("is_enabled", true)
        .single(),
    );
    return row ? rowToArContent(row) : null;
  }

  async findById(id: string): Promise<ArContent | null> {
    const row = await unwrap<Record<string, unknown>>(
      getClient()
        .from("ar_contents")
        .select(SELECT_WITH_GEO)
        .eq("id", id)
        .single(),
    );
    return row ? rowToArContent(row) : null;
  }

  async upsertSpawnZone(
    poiId: string,
    zone: ArContent["spawnZone"],
    reviewedBy: string,
  ): Promise<ArContent> {
    // Use a raw RPC so we can pass the geography via ST_GeomFromGeoJSON.
    // Supabase's .upsert() can't call PostGIS functions in column values.
    const now = new Date().toISOString();
    const geoJson = zoneToGeoJson(zone);

    await unwrap(
      getAdminClient().rpc("upsert_ar_content_zone", {
        p_poi_id: poiId,
        p_spawn_zone: geoJson,
        p_reviewed_by: reviewedBy,
        p_reviewed_at: now,
      }),
    );

    const updated = await this.findByPoiId(poiId);
    if (!updated) throw new Error(`ar_content for poi ${poiId} not found after upsert`);
    return updated;
  }
}

let shared: ArContentRepository | null = null;

export function getArContentRepository(): ArContentRepository {
  if (shared === null) shared = new SupabaseArContentRepository();
  return shared;
}
