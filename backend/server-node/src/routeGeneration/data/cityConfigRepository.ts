/**
 * Layer 5 — City Config Repository.
 *
 * Per-city settings, cached in memory with a short refresh interval (spec §3).
 * This is the mechanism behind the phased city rollout: cluster radius, active
 * routing provider and rollout status all change behaviour without a code
 * change or a deploy (spec §2).
 *
 * Reads go through `public.cities_config` rather than the table: `centre` is
 * the centroid of the `bounding_box` geography column, and PostgREST cannot
 * project a geography. See the note in poiRepository.ts.
 */
import type { SupabaseClient } from "@supabase/supabase-js";

import { getClient } from "../../data/supabaseClient";
import { getLogger } from "../../logger";
import { unwrap } from "../../supabase";
import { CityConfig, RolloutStatus, RoutingProviderName } from "../types";

const logger = getLogger("routeGeneration.cityConfig");

/** Short enough that flipping a city to `active` takes effect within a minute,
 * long enough that the config is not re-read on every request. */
export const CITY_CONFIG_TTL_MS = 60_000;

export interface CityConfigRepository {
  findById(cityId: string): Promise<CityConfig | null>;
  /** Every city that is not soft-deleted, for the city picker. */
  listAll(): Promise<CityConfig[]>;
}

interface CityRow {
  id: string;
  region_id: string | null;
  name: string;
  name_fr: string | null;
  name_ar: string | null;
  centre_lat: number | null;
  centre_lng: number | null;
  cluster_radius_meters: number;
  active_routing_provider: string;
  rollout_status: string;
  feature_flags: Record<string, unknown> | null;
}

function rowToCityConfig(row: CityRow): CityConfig {
  return {
    id: row.id,
    regionId: row.region_id,
    name: row.name,
    nameFr: row.name_fr,
    nameAr: row.name_ar,
    // Null when the city has no bounding_box yet. Left null rather than
    // defaulted to (0,0): the app centres its map on this, and the Gulf of
    // Guinea is a worse answer than "I don't know, use your own position".
    centre:
      row.centre_lat === null || row.centre_lng === null
        ? null
        : { lat: row.centre_lat, lng: row.centre_lng },
    clusterRadiusMeters: row.cluster_radius_meters,
    activeRoutingProvider: row.active_routing_provider as RoutingProviderName,
    rolloutStatus: row.rollout_status as RolloutStatus,
    featureFlags: row.feature_flags ?? {},
  };
}

class SupabaseCityConfigRepository implements CityConfigRepository {
  private get db(): SupabaseClient {
    return getClient();
  }

  async findById(cityId: string): Promise<CityConfig | null> {
    const rows =
      (await unwrap<CityRow[]>(this.db.rpc("cities_config", { p_city_id: cityId }))) ?? [];
    const row = rows[0];
    return row ? rowToCityConfig(row) : null;
  }

  async listAll(): Promise<CityConfig[]> {
    const rows =
      (await unwrap<CityRow[]>(this.db.rpc("cities_config", { p_city_id: null }))) ?? [];
    return rows.map(rowToCityConfig);
  }
}

/** In-memory TTL cache in front of whatever repository it wraps. */
export class CachedCityConfigRepository implements CityConfigRepository {
  private readonly byId = new Map<string, { value: CityConfig | null; storedAt: number }>();
  private all: { value: CityConfig[]; storedAt: number } | null = null;

  constructor(private readonly inner: CityConfigRepository) {}

  async findById(cityId: string): Promise<CityConfig | null> {
    const hit = this.byId.get(cityId);
    if (hit && Date.now() - hit.storedAt < CITY_CONFIG_TTL_MS) {
      return hit.value;
    }
    const value = await this.inner.findById(cityId);
    this.byId.set(cityId, { value, storedAt: Date.now() });
    return value;
  }

  async listAll(): Promise<CityConfig[]> {
    if (this.all && Date.now() - this.all.storedAt < CITY_CONFIG_TTL_MS) {
      return this.all.value;
    }
    const value = await this.inner.listAll();
    this.all = { value, storedAt: Date.now() };
    return value;
  }

  invalidate(): void {
    this.byId.clear();
    this.all = null;
    logger.info("City config cache invalidated");
  }
}

let shared: CityConfigRepository | null = null;

export function getCityConfigRepository(): CityConfigRepository {
  if (shared === null) {
    shared = new CachedCityConfigRepository(new SupabaseCityConfigRepository());
  }
  return shared;
}
