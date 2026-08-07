/**
 * The 8 hand-verified locations, ported from lib/models/location_data.dart.
 *
 * These are seeded into Supabase as `is_curated = true` rows (docs/backend/12)
 * and served from there in the normal case. This module now plays a narrower
 * role: the hardcoded fallback `locationsRepo.ts` degrades to when Supabase is
 * unreachable or misconfigured — "the curated 8 are the floor. Never show an
 * empty map." `distance_km` is intentionally absent here — it's a property of
 * the caller's position, computed via `haversineKm`, not a fact about the
 * place.
 */
import { LocationDetail, LocationRow } from "../types";
import { haversineKm } from "./geo";
import { roundTo } from "../text";

export interface CuratedLocation {
  id: string;
  name: string;
  region: string;
  category: string;
  blurb: string;
  task_type: string;
  task_label: string;
  lat: number;
  lng: number;
}

export const CURATED_LOCATIONS: readonly CuratedLocation[] = [
  {
    id: "casbah",
    name: "Casbah of Algiers",
    region: "Algiers & the Casbah",
    category: "Old town",
    blurb:
      "A UNESCO-listed maze of Ottoman-era alleys, tiled courtyards and " +
      "sea views tumbling down the hillside.",
    task_type: "mascot",
    task_label: "A fennec is hiding in one of these alleys — find it and photograph it",
    lat: 36.7853,
    lng: 3.0608,
  },
  {
    id: "martyrs",
    name: "Maqam Echahid",
    region: "Algiers & the Casbah",
    category: "Monument",
    blurb:
      "Three palm-frond concrete shells rising over the bay, Algiers' " +
      "memorial to independence.",
    task_type: "video",
    task_label: "Film a slow pan across the three palm shells",
    lat: 36.7527,
    lng: 3.0665,
  },
  {
    id: "sidimcid",
    name: "Sidi M'Cid Bridge",
    region: "Constantine",
    category: "Bridge",
    blurb:
      "A suspension bridge slung 175m over the Rhumel gorge, the " +
      "signature view of the City of Bridges.",
    task_type: "video",
    task_label: "Capture a short clip crossing the bridge",
    lat: 36.3705,
    lng: 6.6147,
  },
  {
    id: "ahmedbey",
    name: "Ahmed Bey Palace",
    region: "Constantine",
    category: "Palace",
    blurb:
      "Marble courtyards and painted ceilings inside the last Ottoman " +
      "bey's residence.",
    task_type: "scan",
    task_label: "Scan the painted ceiling medallion",
    lat: 36.3646,
    lng: 6.6088,
  },
  {
    id: "djemila",
    name: "Djemila",
    region: "Djemila & Timgad",
    category: "Roman ruins",
    blurb:
      "A Roman market town scattered across a mountain ridge, its forum " +
      "still catching the evening light.",
    task_type: "scan",
    task_label: "Scan the forum's inscription stone",
    lat: 36.3214,
    lng: 5.7358,
  },
  {
    id: "timgad",
    name: "Timgad",
    region: "Djemila & Timgad",
    category: "Roman ruins",
    blurb:
      "A grid-planned Roman colony known as the Pompeii of Africa, arch " +
      "and colonnade intact.",
    task_type: "video",
    task_label: "Film Trajan's Arch from below",
    lat: 35.4842,
    lng: 6.4675,
  },
  {
    id: "tassili",
    name: "Tassili n'Ajjer",
    region: "Tassili n'Ajjer / Sahara",
    category: "Desert plateau",
    blurb:
      "Sandstone spires and 8,000-year-old rock art scattered across a " +
      "Saharan plateau.",
    task_type: "mascot",
    task_label: "A fennec is hiding on the plateau — find it and photograph it",
    lat: 24.5544,
    lng: 9.4842,
  },
  {
    id: "gouraya",
    name: "Yemma Gouraya",
    region: "Kabylie mountains & coast",
    category: "Coastal peak",
    blurb:
      "A clifftop shrine over the Bay of Bejaia, with the Kabylie " +
      "coastline unrolling below.",
    task_type: "video",
    task_label: "Film the coastline from the shrine",
    lat: 36.7628,
    lng: 5.0921,
  },
];

const LOCATIONS_BY_ID = new Map<string, CuratedLocation>(
  CURATED_LOCATIONS.map((loc) => [loc.id, loc]),
);

export function getLocation(locationId: string): LocationDetail | null {
  const found = LOCATIONS_BY_ID.get(locationId);
  return found ? { ...found } : null;
}

/**
 * Curated locations within `radiusKm`, each annotated with `distance_km`.
 *
 * Falls back to the 5 nearest locations if the radius excludes everything —
 * an empty candidate set is a worse experience than a slightly-too-far
 * suggestion, and this only ever happens with the tiny curated set (real
 * POI data won't need this once ingestion is live, see docs/backend/12).
 */
export function locationsWithinRadius(
  lat: number,
  lng: number,
  radiusKm: number,
  limit?: number | null,
): LocationRow[] {
  const annotated: LocationRow[] = CURATED_LOCATIONS.map((loc) => ({
    ...loc,
    distance_km: roundTo(haversineKm(lat, lng, loc.lat, loc.lng), 1),
  }));

  annotated.sort((a, b) => a.distance_km - b.distance_km);
  const within = annotated.filter((l) => l.distance_km <= radiusKm);
  let result = within.length > 0 ? within : annotated.slice(0, 5);
  if (limit !== undefined && limit !== null) {
    result = result.slice(0, limit);
  }
  return result;
}
