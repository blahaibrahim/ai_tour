/**
 * Layer 5 — Mascot Repository.
 *
 * NOT IN SPEC as its own repository — plan §3's Layer 5 table lists AR
 * Content, Mascot Spawn, Capture, Collection and Push Token repositories,
 * but `ar_contents.mascot_id` and `mascot_spawns.mascot_id` both FK into a
 * `mascots` table that needs its own read path to build a spawn manifest
 * entry's `mascot: {...}` block (plan §7's `SpawnManifestEntry`). Folding it
 * into `ArContentRepository` would mean that repository returning rows from
 * two tables under one name; a small dedicated repository keeps the schema
 * boundary the interface boundary too.
 *
 * STATUS: implemented.
 */
import { getClient } from "../../data/supabaseClient";
import { unwrap, unwrapRows } from "../../supabase";
import { Mascot } from "../types";

export interface MascotRepository {
  findById(id: string): Promise<Mascot | null>;
  findByIds(ids: string[]): Promise<Mascot[]>;
}

/** Maps a mascots row (snake_case) to the domain type (camelCase). */
function rowToMascot(row: Record<string, unknown>): Mascot {
  return {
    id: row.id as string,
    key: row.key as string,
    nameFr: row.name_fr as string,
    nameAr: row.name_ar as string,
    nameEn: row.name_en as string,
    loreFr: (row.lore_fr as string | null) ?? null,
    loreAr: (row.lore_ar as string | null) ?? null,
    loreEn: (row.lore_en as string | null) ?? null,
    rarity: row.rarity as Mascot["rarity"],
    modelGlbRef: row.model_glb_ref as string,
    modelUsdzRef: row.model_usdz_ref as string,
    modelChecksum: row.model_checksum as string,
    scaleMeters: Number(row.scale_meters),
    thumbnailRef: (row.thumbnail_ref as string | null) ?? null,
  };
}

class SupabaseMascotRepository implements MascotRepository {
  async findById(id: string): Promise<Mascot | null> {
    const row = await unwrap<Record<string, unknown>>(
      getClient().from("mascots").select("*").eq("id", id).single(),
    );
    return row ? rowToMascot(row) : null;
  }

  async findByIds(ids: string[]): Promise<Mascot[]> {
    if (ids.length === 0) return [];
    const rows = await unwrapRows<Record<string, unknown>>(
      getClient().from("mascots").select("*").in("id", ids),
    );
    return rows.map(rowToMascot);
  }
}

let shared: MascotRepository | null = null;

export function getMascotRepository(): MascotRepository {
  if (shared === null) shared = new SupabaseMascotRepository();
  return shared;
}
