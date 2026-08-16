import { VOLUME_NAME } from "./config";
import { fetchArtifacts } from "./atlas";
import { reader, supabaseConfigured, type BucketUsage } from "./supabase";
import { listVideos } from "./videos";
import { overview, sceneStatus } from "./volume";

/**
 * Everything the overview tab shows, in one read.
 *
 * The aggregation happens here rather than in Postgres deliberately: these
 * tables are small (tens to low thousands of rows), and a `group by` would
 * mean either a view or an RPC in the app's schema. A dashboard that only
 * looks at a database should not be adding objects to it.
 */

export interface Slice {
  label: string;
  value: number;
}

export interface Totals {
  explorers: number;
  newExplorers30d: number;
  points: number;
  pois: number;
  publishedPois: number;
  poisWithPhoto: number;
  cities: number;
  routes: number;
  routeStops: number;
  routesCompleted: number;
  captures: number;
  models: number;
  savedLocations: number;
  pushTokens: number;
}

export interface SplatState {
  volume: string;
  /** Clips sitting in the dashboard's `videos/` folder. */
  clips: number;
  /** Scenes with a clip in `/raw`. */
  uploaded: number;
  /** Scenes with frames extracted. */
  framed: number;
  /** Scenes with usable SfM output — the gate before any GPU spend. */
  reconstructed: number;
  /** Scenes with at least one `.ply`. */
  trained: number;
  /** How many started scenes were inspected, when there are more than the cap. */
  inspected: number;
  started: number;
  error?: string;
}

export interface Analytics {
  configured: boolean;
  generatedAt: string;
  totals: Totals;
  poisByCategory: Slice[];
  poisByCity: Slice[];
  poisByStatus: Slice[];
  artifactsByKind: Slice[];
  modelJobsByStatus: Slice[];
  routeJobsByStatus: Slice[];
  capturesByWeek: Slice[];
  storage: BucketUsage[];
  splat: SplatState;
  /** Median queue-to-finish for succeeded model jobs, in minutes. */
  modelTurnaroundMinutes: number | null;
  gpuSeconds: number;
  errors: string[];
}

/** Per-scene inspection is three `modal volume ls` calls; cap the fan-out. */
const SCENE_SAMPLE = 12;

function tally(values: (string | null | undefined)[]): Slice[] {
  const counts = new Map<string, number>();
  for (const value of values) {
    const label = value ?? "unknown";
    counts.set(label, (counts.get(label) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value);
}

/** Monday of the week a timestamp falls in, as `YYYY-MM-DD`. */
function weekStart(iso: string): string {
  const date = new Date(iso);
  const day = (date.getUTCDay() + 6) % 7;
  date.setUTCDate(date.getUTCDate() - day);
  return date.toISOString().slice(0, 10);
}

function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
}

export async function buildAnalytics(): Promise<Analytics> {
  const db = reader();
  const thirtyDaysAgo = new Date(Date.now() - 30 * 86_400_000).toISOString();

  const [
    profiles,
    poiRows,
    categories,
    cities,
    artifacts,
    modelJobs,
    routeJobs,
    routes,
    routeStops,
    progress,
    savedLocations,
    pushTokens,
    storage,
    clips,
    volume,
  ] = await Promise.all([
    db.select<{ total_points: number; created_at: string }>("profiles", {
      select: "total_points,created_at",
      limit: "10000",
    }),
    db.select<{ category_id: string; city_id: string; status: string; photo_url: string | null }>(
      "pois",
      {
        select: "category_id,city_id,status,photo_url",
        deleted_at: "is.null",
        limit: "5000",
      },
    ),
    db.select<{ id: string; label_en: string }>("categories", {
      select: "id,label_en",
    }),
    db.select<{ id: string; name: string }>("cities", { select: "id,name" }),
    fetchArtifacts(db),
    db.select<{
      status: string;
      gpu_seconds: number | string | null;
      queued_at: string;
      finished_at: string | null;
    }>("model_jobs", {
      select: "status,gpu_seconds,queued_at,finished_at",
      limit: "5000",
    }),
    db.select<{ status: string }>("route_jobs", {
      select: "status",
      limit: "5000",
    }),
    db.count("routes"),
    db.count("route_stops"),
    db.select<{ status: string }>("progress", { select: "status", limit: "5000" }),
    db.count("saved_locations"),
    db.count("push_tokens"),
    db.storageUsage(),
    listVideos(),
    overview(),
  ]);

  const categoryById = new Map(categories.map((row) => [row.id, row.label_en]));
  const cityById = new Map(cities.map((row) => [row.id, row.name]));

  // The Volume's `/scenes` listing says a scene was started, not how far it
  // got — that needs a look inside each one, which is why it is sampled.
  const sample = volume.started.slice(0, SCENE_SAMPLE);
  const scenes = await Promise.all(sample.map((scene) => sceneStatus(scene)));

  const turnarounds = modelJobs
    .filter((job) => job.status === "succeeded" && job.finished_at)
    .map(
      (job) =>
        (Date.parse(job.finished_at!) - Date.parse(job.queued_at)) / 60_000,
    )
    .filter((minutes) => Number.isFinite(minutes) && minutes >= 0);

  return {
    configured: supabaseConfigured(),
    generatedAt: new Date().toISOString(),

    totals: {
      explorers: profiles.length,
      newExplorers30d: profiles.filter((row) => row.created_at >= thirtyDaysAgo)
        .length,
      points: profiles.reduce((sum, row) => sum + (row.total_points ?? 0), 0),
      pois: poiRows.length,
      publishedPois: poiRows.filter((row) => row.status === "published").length,
      poisWithPhoto: poiRows.filter((row) => row.photo_url).length,
      cities: cities.length,
      routes,
      routeStops,
      routesCompleted: progress.filter((row) => row.status === "completed").length,
      captures: artifacts.filter((row) => row.kind !== "model").length,
      models: artifacts.filter((row) => row.kind === "model" && row.model_path)
        .length,
      savedLocations,
      pushTokens,
    },

    poisByCategory: tally(
      poiRows.map((row) => categoryById.get(row.category_id) ?? "Other"),
    ),
    poisByCity: tally(poiRows.map((row) => cityById.get(row.city_id) ?? "—")),
    poisByStatus: tally(poiRows.map((row) => row.status)),
    artifactsByKind: tally(artifacts.map((row) => row.kind)),
    modelJobsByStatus: tally(modelJobs.map((row) => row.status)),
    routeJobsByStatus: tally(routeJobs.map((row) => row.status)),

    capturesByWeek: (() => {
      const weeks = tally(artifacts.map((row) => weekStart(row.captured_at)));
      // Chronological, and only the recent stretch — a sparkline of every week
      // since the project started would be mostly empty.
      return weeks.sort((a, b) => a.label.localeCompare(b.label)).slice(-12);
    })(),

    storage,

    splat: {
      volume: VOLUME_NAME,
      clips: clips.length,
      uploaded: volume.uploaded.length,
      started: volume.started.length,
      inspected: sample.length,
      framed: scenes.filter((scene) => scene.frames > 0).length,
      reconstructed: scenes.filter((scene) => scene.sfm).length,
      trained: scenes.filter((scene) => scene.plys.length > 0).length,
      error: volume.error,
    },

    modelTurnaroundMinutes: median(turnarounds),
    gpuSeconds: modelJobs.reduce(
      (sum, job) => sum + (Number(job.gpu_seconds) || 0),
      0,
    ),

    errors: db.errors(),
  };
}
