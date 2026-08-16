import { invert, readAssignments } from "./assignments";
import { decodePoint, reader, signStoragePaths, type Reader } from "./supabase";
import { listVideos, type VideoFile } from "./videos";
import { loadWilayas, nearestWilaya, wilayaAt } from "./wilayas";

/**
 * The map view's data: Algeria's wilayas, the POIs inside each, and what has
 * been captured at each POI.
 *
 * Two sources meet here. POIs, categories and cities come from Supabase;
 * captures come from Supabase *and* from the local `videos/` folder, because a
 * clip that has not been uploaded anywhere is still the input the splat
 * pipeline runs on. Which POI a capture belongs to comes from
 * `lib/assignments.ts` — see that file for why it isn't a column.
 */

export interface PoiMediaCounts {
  /** Local clips assigned to this POI, i.e. splat pipeline input. */
  clips: number;
  /** Photos and videos captured in the app by explorers. */
  captures: number;
  /** Finished 3D models (GLB) attached to this POI. */
  models: number;
}

export interface AtlasPoi {
  id: string;
  name: string;
  nameAr: string | null;
  nameFr: string | null;
  description: string | null;
  categoryKey: string;
  categoryLabel: string;
  city: string;
  status: string;
  lat: number;
  lon: number;
  wilayaCode: string | null;
  interestScore: number | null;
  visitMinutes: number | null;
  photoUrl: string | null;
  counts: PoiMediaCounts;
}

export interface AtlasWilaya {
  code: string;
  name: string;
  poiCount: number;
  counts: PoiMediaCounts;
}

export interface Atlas {
  wilayas: AtlasWilaya[];
  pois: AtlasPoi[];
  /** Clips in `videos/` not yet attached to a POI. */
  unassignedClips: string[];
  /** Supabase captures not yet attached to a POI. */
  unassignedArtifacts: number;
  /**
   * Clip filename -> POI id, in full. The studio needs the reverse lookup to
   * jump to whichever stop a running job's clip belongs to, which is not
   * answerable from the per-stop detail endpoint alone.
   */
  clipOwners: Record<string, string>;
  errors: string[];
}

interface PoiRow {
  id: string;
  city_id: string;
  category_id: string;
  name_en: string | null;
  name_fr: string | null;
  name_ar: string | null;
  description_en: string | null;
  location: unknown;
  status: string;
  photo_url: string | null;
  interest_score: number | string | null;
  avg_visit_duration_minutes: number | null;
}

export interface ArtifactRow {
  id: string;
  user_id: string;
  kind: string;
  title: string | null;
  image_path: string | null;
  model_path: string | null;
  captured_at: string;
  deleted_at: string | null;
}

/** Every live capture, newest first. Shared with the analytics view. */
export async function fetchArtifacts(db: Reader): Promise<ArtifactRow[]> {
  return db.select<ArtifactRow>("artifacts", {
    select: "id,user_id,kind,title,image_path,model_path,captured_at,deleted_at",
    deleted_at: "is.null",
    order: "captured_at.desc",
    limit: "2000",
  });
}

export async function buildAtlas(): Promise<Atlas> {
  const db = reader();

  const [wilayas, poiRows, categories, cities, artifacts, assignments, clips] =
    await Promise.all([
      loadWilayas(),
      db.select<PoiRow>("pois", {
        select:
          "id,city_id,category_id,name_en,name_fr,name_ar,description_en," +
          "location,status,photo_url,interest_score,avg_visit_duration_minutes",
        deleted_at: "is.null",
        limit: "5000",
      }),
      db.select<{ id: string; key: string; label_en: string }>("categories", {
        select: "id,key,label_en",
      }),
      db.select<{ id: string; name: string }>("cities", { select: "id,name" }),
      fetchArtifacts(db),
      readAssignments(),
      listVideos(),
    ]);

  const categoryById = new Map(categories.map((row) => [row.id, row]));
  const cityById = new Map(cities.map((row) => [row.id, row.name]));
  const artifactById = new Map(artifacts.map((row) => [row.id, row]));

  const clipsByPoi = invert(assignments.clips);
  const artifactsByPoi = invert(assignments.artifacts);

  const pois: AtlasPoi[] = [];
  for (const row of poiRows) {
    const point = decodePoint(row.location);
    if (!point) continue;

    // A POI just off a simplified coastline falls outside every polygon; put
    // it in the wilaya it is nearest to rather than dropping it off the map.
    const wilaya =
      wilayaAt(wilayas, point.lat, point.lon) ??
      nearestWilaya(wilayas, point.lat, point.lon);

    const assigned = (artifactsByPoi.get(row.id) ?? [])
      .map((id) => artifactById.get(id))
      .filter((artifact): artifact is ArtifactRow => Boolean(artifact));

    pois.push({
      id: row.id,
      name: row.name_en ?? row.name_fr ?? row.name_ar ?? "Untitled",
      nameAr: row.name_ar,
      nameFr: row.name_fr,
      description: row.description_en,
      categoryKey: categoryById.get(row.category_id)?.key ?? "other",
      categoryLabel: categoryById.get(row.category_id)?.label_en ?? "Other",
      city: cityById.get(row.city_id) ?? "—",
      status: row.status,
      lat: point.lat,
      lon: point.lon,
      wilayaCode: wilaya?.code ?? null,
      interestScore:
        row.interest_score === null ? null : Number(row.interest_score),
      visitMinutes: row.avg_visit_duration_minutes,
      photoUrl: row.photo_url,
      counts: {
        clips: (clipsByPoi.get(row.id) ?? []).length,
        captures: assigned.filter((a) => a.kind !== "model").length,
        models: assigned.filter((a) => a.kind === "model" && a.model_path).length,
      },
    });
  }

  const byWilaya = new Map<string, AtlasWilaya>();
  for (const wilaya of wilayas) {
    byWilaya.set(wilaya.code, {
      code: wilaya.code,
      name: wilaya.name,
      poiCount: 0,
      counts: { clips: 0, captures: 0, models: 0 },
    });
  }
  for (const poi of pois) {
    const entry = poi.wilayaCode ? byWilaya.get(poi.wilayaCode) : undefined;
    if (!entry) continue;
    entry.poiCount += 1;
    entry.counts.clips += poi.counts.clips;
    entry.counts.captures += poi.counts.captures;
    entry.counts.models += poi.counts.models;
  }

  return {
    wilayas: [...byWilaya.values()].sort((a, b) => a.code.localeCompare(b.code)),
    pois: pois.sort((a, b) => a.name.localeCompare(b.name)),
    unassignedClips: clips
      .map((clip) => clip.file)
      .filter((file) => !assignments.clips[file]),
    unassignedArtifacts: artifacts.filter(
      (artifact) => !assignments.artifacts[artifact.id],
    ).length,
    clipOwners: assignments.clips,
    errors: db.errors(),
  };
}

export interface PoiCapture {
  id: string;
  kind: string;
  title: string;
  capturedAt: string;
  /** Signed, short-lived. Null when the object is gone or signing failed. */
  imageUrl: string | null;
  modelUrl: string | null;
}

export interface PoiDetail {
  clips: VideoFile[];
  captures: PoiCapture[];
  errors: string[];
}

/**
 * Everything captured at one POI: the local clips the splat pipeline runs on,
 * and the app captures explorers uploaded. Splat status per clip is left to
 * `/api/scenes/[scene]` — it costs three `modal volume ls` calls apiece, so it
 * is fetched per scene, on demand, rather than for the whole POI up front.
 */
export async function poiDetail(poiId: string): Promise<PoiDetail> {
  const db = reader();
  const [assignments, videos, artifacts] = await Promise.all([
    readAssignments(),
    listVideos(),
    fetchArtifacts(db),
  ]);

  const clipNames = new Set(
    Object.entries(assignments.clips)
      .filter(([, id]) => id === poiId)
      .map(([file]) => file),
  );
  const artifactIds = new Set(
    Object.entries(assignments.artifacts)
      .filter(([, id]) => id === poiId)
      .map(([id]) => id),
  );

  const mine = artifacts.filter((artifact) => artifactIds.has(artifact.id));
  const signed = await signStoragePaths(
    db,
    mine.flatMap((artifact) => [artifact.image_path, artifact.model_path]),
  );

  return {
    clips: videos.filter((video) => clipNames.has(video.file)),
    captures: mine.map((artifact) => ({
      id: artifact.id,
      kind: artifact.kind,
      title: artifact.title?.trim() || "capture",
      capturedAt: artifact.captured_at,
      imageUrl: signed.get(artifact.image_path ?? "") ?? null,
      modelUrl: signed.get(artifact.model_path ?? "") ?? null,
    })),
    errors: db.errors(),
  };
}
