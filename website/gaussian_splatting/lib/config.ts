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
