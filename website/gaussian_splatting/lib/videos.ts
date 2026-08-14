import fs from "node:fs/promises";
import path from "node:path";

import { VIDEO_DIR, VIDEO_EXTENSIONS } from "./config";
import { sceneNameFor } from "./pipeline";

export interface VideoFile {
  /** Basename, e.g. `plaza.mp4`. The id used by every route. */
  file: string;
  /** What the clip becomes in the Volume: `/raw/<scene>.<ext>`. */
  scene: string;
  sizeBytes: number;
  modifiedAt: string;
}

export async function listVideos(): Promise<VideoFile[]> {
  let entries;
  try {
    entries = await fs.readdir(VIDEO_DIR, { withFileTypes: true });
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      await fs.mkdir(VIDEO_DIR, { recursive: true });
      return [];
    }
    throw err;
  }

  const videos = await Promise.all(
    entries
      .filter(
        (entry) =>
          entry.isFile() &&
          VIDEO_EXTENSIONS.includes(path.extname(entry.name).toLowerCase()),
      )
      .map(async (entry) => {
        const stat = await fs.stat(path.join(VIDEO_DIR, entry.name));
        return {
          file: entry.name,
          scene: sceneNameFor(entry.name),
          sizeBytes: stat.size,
          modifiedAt: stat.mtime.toISOString(),
        };
      }),
  );

  return videos.sort((a, b) => b.modifiedAt.localeCompare(a.modifiedAt));
}

/**
 * Resolve a request's filename to a path inside [VIDEO_DIR], or null.
 *
 * Checked against the actual listing rather than by sanitising the string:
 * this path is handed to `createReadStream` and to `modal volume put`, and a
 * membership test is the one form of validation that cannot be walked out of.
 */
export async function resolveVideo(file: string): Promise<VideoFile | null> {
  const videos = await listVideos();
  return videos.find((video) => video.file === file) ?? null;
}

export function absolutePathOf(video: VideoFile): string {
  return path.join(VIDEO_DIR, video.file);
}
