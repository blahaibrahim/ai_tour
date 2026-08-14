import { execFile } from "node:child_process";
import path from "node:path";
import { promisify } from "node:util";

import { MODAL_BIN, VOLUME_NAME } from "./config";

const execFileAsync = promisify(execFile);

/** One row of `modal volume ls --json`. */
interface VolumeEntry {
  Filename: string;
  Type: string;
  "Created/Modified": string;
  /** Already humanised by the CLI, e.g. "1.2 MiB". */
  Size: string;
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
      { timeout: 30_000, windowsHide: true, maxBuffer: 8 * 1024 * 1024 },
    );
    return { available: true, entries: JSON.parse(stdout) as VolumeEntry[] };
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
  return listing.entries.map((entry) => path.posix.basename(entry.Filename));
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
  plys: { name: string; size: string }[];
  error?: string;
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

  return {
    scene,
    frames: frames.entries.length,
    sfm: sfm.entries.length > 0,
    plys: output.entries
      .filter((entry) => entry.Filename.endsWith(".ply"))
      .map((entry) => ({
        name: path.posix.basename(entry.Filename),
        size: entry.Size,
      })),
    error: frames.error ?? sfm.error ?? output.error,
  };
}
