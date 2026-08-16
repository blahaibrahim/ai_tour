import fs from "node:fs/promises";
import path from "node:path";

import { VIDEO_DIR } from "./config";

/**
 * Which POI a clip is a capture of.
 *
 * **This lives in a file rather than in the database, and that is a
 * workaround.** The app's schema has no edge from a capture to a POI:
 * `artifacts.location_id` points at `locations`, the discovery-pipeline
 * catalogue, which is empty — while the map, the routes and this dashboard all
 * run on `pois`. Adding `artifacts.poi_id` is the durable fix, and it belongs
 * in a migration alongside the app change that starts writing it, not in a
 * dashboard.
 *
 * Until then the mapping is dashboard-owned and local: a JSON file next to the
 * clips, holding two maps. It is additive, reversible, and the day the column
 * exists this module is deleted rather than migrated.
 */

export interface Assignments {
  /** Local clip filename -> POI id. */
  clips: Record<string, string>;
  /** Supabase `artifacts.id` -> POI id, for captures already in the project. */
  artifacts: Record<string, string>;
}

const FILE = path.join(VIDEO_DIR, "assignments.json");

const EMPTY: Assignments = { clips: {}, artifacts: {} };

export async function readAssignments(): Promise<Assignments> {
  try {
    const parsed = JSON.parse(await fs.readFile(FILE, "utf8")) as Partial<Assignments>;
    return {
      clips: parsed.clips ?? {},
      artifacts: parsed.artifacts ?? {},
    };
  } catch (err) {
    // A missing file is the normal first-run state. Anything else — malformed
    // JSON, a permissions problem — is worth surfacing rather than silently
    // starting from nothing and overwriting it on the next assignment.
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return { ...EMPTY };
    throw new Error(`could not read ${FILE}: ${(err as Error).message}`);
  }
}

/**
 * Assign one clip or artifact to a POI, or clear it by passing `null`.
 *
 * Read-modify-write, which is safe here for the reason the job queue is
 * serial: this is a single-operator local tool, and the alternative would be
 * locking a file that one browser tab writes.
 */
export async function assign(
  kind: "clips" | "artifacts",
  key: string,
  poiId: string | null,
): Promise<Assignments> {
  const current = await readAssignments();
  if (poiId) {
    current[kind][key] = poiId;
  } else {
    delete current[kind][key];
  }

  await fs.mkdir(VIDEO_DIR, { recursive: true });
  await fs.writeFile(FILE, `${JSON.stringify(current, null, 2)}\n`, "utf8");
  return current;
}

/** POI id -> the keys assigned to it, which is the direction every read wants. */
export function invert(map: Record<string, string>): Map<string, string[]> {
  const byPoi = new Map<string, string[]>();
  for (const [key, poiId] of Object.entries(map)) {
    byPoi.set(poiId, [...(byPoi.get(poiId) ?? []), key]);
  }
  return byPoi;
}
