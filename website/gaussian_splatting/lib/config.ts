import path from "node:path";

/** Server-side configuration. Everything is overridable from `.env.local`. */

/** The Modal Volume the pipeline reads and writes. */
export const VOLUME_NAME = process.env.GSPLAT_VOLUME ?? "gsplat-data";

/**
 * The `modal` CLI. This dashboard is a front end for that binary and nothing
 * else — it never talks to Modal's API directly, so whatever profile/token the
 * CLI is already using is the one that gets billed.
 */
export const MODAL_BIN = process.env.MODAL_BIN ?? "modal";

// Both paths point outside the bundle on purpose — this dashboard drives a
// checkout, not a deployment. The ignore comments stop the build from tracing
// them and pulling half the repo into the server output.

/** Where `modal_app.py` lives; `modal run` is spawned with this as its cwd. */
export const PIPELINE_DIR = path.resolve(
  /* turbopackIgnore: true */
  process.env.GSPLAT_PIPELINE_DIR ??
    path.join(process.cwd(), "..", "..", "backend", "gaussian_splatting"),
);

/** Local clips the dashboard lists and plays. */
export const VIDEO_DIR = path.resolve(
  /* turbopackIgnore: true */
  process.env.GSPLAT_VIDEO_DIR ?? path.join(process.cwd(), "videos"),
);

/**
 * Where `modal volume get` drops a `.ply` so the browser can render it. Kept
 * out of `videos/` because a splat is an output, not a capture, and out of
 * `public/` because Next serves that directory statically at build time —
 * a file fetched after `next dev` started would never be picked up.
 */
export const SPLAT_CACHE_DIR = path.resolve(
  /* turbopackIgnore: true */
  process.env.GSPLAT_CACHE_DIR ?? path.join(process.cwd(), ".splats"),
);

/**
 * Whether a finished run pulls the point clouds it produced onto this machine
 * without being asked.
 *
 * On by default. The Volume is the durable copy, but a splat you have paid GPU
 * minutes for and cannot open is not much of a result — and by the time a run
 * succeeds the download is the cheap part. Set `GSPLAT_AUTO_FETCH=0` if you are
 * on a metered connection or only care about the Volume copy.
 */
export const AUTO_FETCH_SPLATS = process.env.GSPLAT_AUTO_FETCH !== "0";

export const VIDEO_EXTENSIONS = [".mp4", ".mov", ".m4v", ".webm", ".mkv"];

export const MIME_TYPES: Record<string, string> = {
  ".mp4": "video/mp4",
  ".m4v": "video/mp4",
  ".mov": "video/quicktime",
  ".webm": "video/webm",
  ".mkv": "video/x-matroska",
};

/** Lines of a job's output kept in memory. Enough to see a whole SfM run. */
export const MAX_LOG_LINES = 2_000;

/**
 * Environment for every `modal` child process.
 *
 * `PYTHONIOENCODING` is load-bearing on Windows, not a nicety. The Modal CLI
 * prints "✓" on a successful upload; when its stdout is a pipe rather than a
 * console, Python picks the ANSI code page (cp1252 here), fails to encode the
 * character, and the CLI dies with a UnicodeEncodeError — turning a finished
 * upload into a non-zero exit and a failed run. Observed on this machine with
 * `modal volume put`.
 */
export const MODAL_ENV: Record<string, string> = {
  PYTHONUNBUFFERED: "1",
  PYTHONIOENCODING: "utf-8",
  TERM: "dumb",
};

/**
 * Supabase, read-only and server-side only.
 *
 * The key is `service_role` on purpose: the analytics this dashboard shows
 * (every explorer's captures, every model job, storage usage) is exactly what
 * RLS hides from `anon`. That is also why none of it is ever exposed with a
 * `NEXT_PUBLIC_` name — the browser gets aggregates and signed URLs, never the
 * key. Run this dashboard locally; it is not something to deploy publicly.
 */
export const SUPABASE_URL = (process.env.SUPABASE_URL ?? "").replace(/\/+$/, "");
export const SUPABASE_SERVICE_ROLE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";

/** How long a signed capture/model URL handed to the browser stays valid. */
export const SIGNED_URL_TTL_SECONDS = 60 * 60;
