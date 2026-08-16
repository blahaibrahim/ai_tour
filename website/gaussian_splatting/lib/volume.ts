import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

import { MODAL_BIN, MODAL_ENV, SPLAT_CACHE_DIR, VOLUME_NAME } from "./config";

const execFileAsync = promisify(execFile);

/**
 * One row of `modal volume ls --json`, normalised.
 *
 * The CLI's own key casing is not stable across versions — 1.5.2 emits
 * `filename` / `size`, and this code was originally written against the
 * capitalised `Filename` / `Size`. Reading the wrong one yields `undefined`
 * rather than an error, so the bug stays completely invisible until a listing
 * is non-empty and then throws deep inside a `.map`. Both spellings are
 * accepted here, once, and nothing downstream touches the raw shape.
 */
interface VolumeEntry {
  /** Volume-relative, and not always leading-slashed. */
  filename: string;
  type: string;
  /** Already humanised by the CLI, e.g. "1.2 MiB". */
  size: string;
}

interface RawEntry {
  filename?: unknown;
  Filename?: unknown;
  type?: unknown;
  Type?: unknown;
  size?: unknown;
  Size?: unknown;
}

function normalise(rows: unknown): VolumeEntry[] {
  if (!Array.isArray(rows)) return [];

  return rows.flatMap((row: RawEntry) => {
    const filename = row?.filename ?? row?.Filename;
    // A row with no name at all is one this code cannot place; skip it rather
    // than crash the listing it arrived in.
    if (typeof filename !== "string" || !filename) return [];
    return [
      {
        filename,
        type: String(row.type ?? row.Type ?? ""),
        size: String(row.size ?? row.Size ?? ""),
      },
    ];
  });
}

export interface VolumeListing {
  /** False when the Volume does not exist yet — it is created on the first run. */
  available: boolean;
  entries: VolumeEntry[];
  error?: string;
}

/**
 * `modal volume ls`, tolerant of the two failures that are not really failures:
 * a Volume that has not been created yet, and a path inside it that nothing has
 * written to yet. Both mean "nothing here", which is a normal state for a
 * pipeline that caches its stages.
 */
export async function listPath(remotePath: string): Promise<VolumeListing> {
  try {
    const { stdout } = await execFileAsync(
      MODAL_BIN,
      ["volume", "ls", VOLUME_NAME, remotePath, "--json"],
      {
        timeout: 30_000,
        windowsHide: true,
        maxBuffer: 8 * 1024 * 1024,
        env: { ...process.env, ...MODAL_ENV },
      },
    );
    return { available: true, entries: normalise(JSON.parse(stdout)) };
  } catch (err) {
    const error = err as NodeJS.ErrnoException & { stderr?: string };
    const message = `${error.stderr ?? ""}${error.message ?? ""}`;

    if (error.code === "ENOENT") {
      return {
        available: false,
        entries: [],
        error:
          `could not run '${MODAL_BIN}' — install the Modal client ` +
          "(pip install -r backend/gaussian_splatting/requirements-local.txt) " +
          "or set MODAL_BIN to its full path",
      };
    }
    if (/not found|No such file|does not exist/i.test(message)) {
      // Missing volume or missing path: nothing has been uploaded yet.
      return { available: false, entries: [] };
    }
    return { available: false, entries: [], error: message.trim().slice(-500) };
  }
}

/** Basenames of the entries at a Volume path. */
function namesIn(listing: VolumeListing): string[] {
  return listing.entries.map((entry) => path.posix.basename(entry.filename));
}

export interface VolumeOverview {
  /** Scene names with a clip uploaded to `/raw`. */
  uploaded: string[];
  /** Scene names with a directory under `/scenes`. */
  started: string[];
  error?: string;
}

/** One round trip per top-level directory, for the badges on the video grid. */
export async function overview(): Promise<VolumeOverview> {
  const [raw, scenes] = await Promise.all([
    listPath("/raw"),
    listPath("/scenes"),
  ]);

  return {
    uploaded: namesIn(raw).map((name) => name.replace(/\.[^.]+$/, "")),
    started: namesIn(scenes),
    error: raw.error ?? scenes.error,
  };
}

export interface SceneStatus {
  scene: string;
  /** Frames extracted, or 0 when the stage has not run. */
  frames: number;
  /** True once SfM has produced undistorted images — what training reads. */
  sfm: boolean;
  /** Point clouds in `output/`, newest naming first. */
  plys: { name: string; size: string; cached: boolean }[];
  error?: string;
}

/** Where a fetched `.ply` lands. Scene and name are both validated by callers. */
export function cachedSplatPath(scene: string, name: string): string {
  return path.join(SPLAT_CACHE_DIR, scene, name);
}

async function exists(file: string): Promise<boolean> {
  try {
    await fs.access(file);
    return true;
  } catch {
    return false;
  }
}

/** Splats already pulled down for this scene, newest naming last. */
async function cachedSplats(
  scene: string,
): Promise<{ name: string; size: string; cached: boolean }[]> {
  let entries: string[];
  try {
    entries = await fs.readdir(path.join(SPLAT_CACHE_DIR, scene));
  } catch {
    return [];
  }

  return Promise.all(
    entries
      .filter((name) => name.endsWith(".ply"))
      .map(async (name) => {
        const { size } = await fs.stat(cachedSplatPath(scene, name));
        return {
          name,
          // Matches how the CLI humanises it, so the two sources read alike.
          size: `${(size / 1024 ** 2).toFixed(1)} MiB`,
          cached: true,
        };
      }),
  );
}

/**
 * `modal volume get` one `.ply` into the local cache, so the viewer has
 * something to render.
 *
 * A splat is tens to hundreds of MB and the browser has to have the whole file
 * before it can draw a frame, so it is copied down once and served locally
 * rather than streamed through this server on every page view.
 */
export async function fetchSplat(scene: string, name: string): Promise<string> {
  const local = cachedSplatPath(scene, name);
  if (await exists(local)) return local;

  await fs.mkdir(path.dirname(local), { recursive: true });
  const remote = `/scenes/${scene}/output/${name}`;

  try {
    await execFileAsync(
      MODAL_BIN,
      ["volume", "get", VOLUME_NAME, remote, local, "--force"],
      // Generous: this is a large file over the network, and the alternative
      // to waiting is a half-written .ply the viewer would choke on.
      {
        timeout: 15 * 60_000,
        windowsHide: true,
        maxBuffer: 8 * 1024 * 1024,
        env: { ...process.env, ...MODAL_ENV },
      },
    );
  } catch (err) {
    const error = err as NodeJS.ErrnoException & { stderr?: string };
    // Never leave a truncated file behind: it would look cached next time.
    await fs.rm(local, { force: true });
    throw new Error(
      error.code === "ENOENT"
        ? `could not run '${MODAL_BIN}' — install the Modal client or set MODAL_BIN`
        : `${error.stderr ?? error.message}`.trim().slice(-400),
    );
  }

  return local;
}

/**
 * What of a scene is already cached in the Volume. The CLI skips stages whose
 * output is present, so this is also what makes the cost estimate honest.
 */
export async function sceneStatus(scene: string): Promise<SceneStatus> {
  const base = `/scenes/${scene}`;
  const [frames, sfm, output] = await Promise.all([
    listPath(`${base}/frames`),
    listPath(`${base}/sfm/undistorted/images`),
    listPath(`${base}/output`),
  ]);

  const plys = await Promise.all(
    output.entries
      .filter((entry) => entry.filename.endsWith(".ply"))
      .map(async (entry) => {
        const name = path.posix.basename(entry.filename);
        return {
          name,
          size: entry.size,
          cached: await exists(cachedSplatPath(scene, name)),
        };
      }),
  );

  // A splat already fetched stays viewable even when the Volume cannot be
  // listed — no Modal client installed, no network, wrong profile. The local
  // copy is a real file on disk and the viewer needs nothing else.
  for (const local of await cachedSplats(scene)) {
    if (!plys.some((ply) => ply.name === local.name)) plys.push(local);
  }

  return {
    scene,
    frames: frames.entries.length,
    sfm: sfm.entries.length > 0,
    plys,
    error: frames.error ?? sfm.error ?? output.error,
  };
}
