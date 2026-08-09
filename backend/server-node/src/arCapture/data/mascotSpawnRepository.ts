/**
 * Layer 5 — Mascot Spawn Repository. Spawn instances per route, immutable
 * once generated, like `routes` (plan §3, §7).
 *
 * GEOGRAPHY column: `location GEOGRAPHY(POINT, 4326)`.
 * Read: ST_AsGeoJSON returns {"type":"Point","coordinates":[lng,lat]}.
 * Write: we pass `ST_MakePoint(lng, lat)::geography` via a raw execute call
 * because supabase-js .insert() cannot call PostGIS functions inline.
 * To keep the insert simple, we use a helper RPC `insert_mascot_spawn`.
 *
 * STATUS: implemented.
 */
import { getAdminClient } from "../../ingestion/supabaseAdmin";
import { getClient } from "../../data/supabaseClient";
import { unwrap, unwrapRows } from "../../supabase";
import { MascotSpawn } from "../types";

export interface MascotSpawnRepository {
  findActiveByRoute(routeId: string): Promise<MascotSpawn[]>;
  findById(spawnId: string): Promise<MascotSpawn | null>;
  /** `UNIQUE (route_id, poi_id)` in the schema makes this idempotent per
   * route/POI pair — a second call for the same pair returns the first
   * spawn rather than creating a duplicate. */
  persist(spawn: Omit<MascotSpawn, "id" | "createdAt">): Promise<MascotSpawn>;
  markCaptured(spawnId: string): Promise<void>;
}

const SELECT_WITH_GEO =
  "id, route_id, poi_id, ar_content_id, mascot_id, " +
  "ST_AsGeoJSON(location)::jsonb as location, " +
  "spawn_seed, spawn_epoch, state, expires_at, created_at";

function parsePoint(raw: unknown): { lat: number; lng: number } {
  try {
    const gj = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (gj && (gj as { coordinates?: unknown }).coordinates) {
      const [lng, lat] = (gj as { coordinates: [number, number] }).coordinates;
      return { lat, lng };
    }
  } catch {
    // fall through
  }
  return { lat: 0, lng: 0 };
}

function rowToSpawn(row: Record<string, unknown>): MascotSpawn {
  return {
    id: row.id as string,
    routeId: row.route_id as string,
    poiId: row.poi_id as string,
    arContentId: row.ar_content_id as string,
    mascotId: row.mascot_id as string,
    location: parsePoint(row.location),
    spawnSeed: row.spawn_seed as string,
    spawnEpoch: row.spawn_epoch as string,
    state: row.state as MascotSpawn["state"],
    expiresAt: (row.expires_at as string | null) ?? null,
    createdAt: row.created_at as string,
  };
}

class SupabaseMascotSpawnRepository implements MascotSpawnRepository {
  async findActiveByRoute(routeId: string): Promise<MascotSpawn[]> {
    const rows = await unwrapRows<Record<string, unknown>>(
      getClient()
        .from("mascot_spawns")
        .select(SELECT_WITH_GEO)
        .eq("route_id", routeId)
        .eq("state", "active"),
    );
    return rows.map(rowToSpawn);
  }

  async findById(spawnId: string): Promise<MascotSpawn | null> {
    const row = await unwrap<Record<string, unknown>>(
      getClient()
        .from("mascot_spawns")
        .select(SELECT_WITH_GEO)
        .eq("id", spawnId)
        .single(),
    );
    return row ? rowToSpawn(row) : null;
  }

  async persist(spawn: Omit<MascotSpawn, "id" | "createdAt">): Promise<MascotSpawn> {
    // Try to find an existing spawn first (idempotency: UNIQUE (route_id, poi_id))
    const existing = await unwrap<Record<string, unknown>>(
      getAdminClient()
        .from("mascot_spawns")
        .select(SELECT_WITH_GEO)
        .eq("route_id", spawn.routeId)
        .eq("poi_id", spawn.poiId)
        .single(),
    );
    if (existing) return rowToSpawn(existing);

    // Insert via RPC so PostGIS can handle the geography column.
    const row = await unwrap<Record<string, unknown>>(
      getAdminClient().rpc("insert_mascot_spawn", {
        p_route_id: spawn.routeId,
        p_poi_id: spawn.poiId,
        p_ar_content_id: spawn.arContentId,
        p_mascot_id: spawn.mascotId,
        p_lng: spawn.location.lng,
        p_lat: spawn.location.lat,
        p_spawn_seed: spawn.spawnSeed,
        p_spawn_epoch: spawn.spawnEpoch,
        p_state: spawn.state,
        p_expires_at: spawn.expiresAt,
      }),
    );
    if (!row) throw new Error("insert_mascot_spawn returned no row");
    return rowToSpawn(row as Record<string, unknown>);
  }

  async markCaptured(spawnId: string): Promise<void> {
    await unwrap(
      getAdminClient()
        .from("mascot_spawns")
        .update({ state: "captured" })
        .eq("id", spawnId),
    );
  }
}

let shared: MascotSpawnRepository | null = null;

export function getMascotSpawnRepository(): MascotSpawnRepository {
  if (shared === null) shared = new SupabaseMascotSpawnRepository();
  return shared;
}
