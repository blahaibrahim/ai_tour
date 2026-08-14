/**
 * Facts about the pipeline that both the browser and the server need.
 *
 * Every constant here is mirrored from `backend/gaussian_splatting/modal_app.py`,
 * which stays the source of truth — this dashboard only ever *drives* the CLI,
 * it never reimplements a stage. If a preset changes there, change it here too;
 * the only thing that breaks is the estimate shown before you spend.
 */

export type Quality = "draft" | "high";
export type SceneType = "outdoor" | "indoor";
export type Stage = "frames" | "sfm" | "train" | "all";

export const QUALITIES: Quality[] = ["draft", "high"];
export const SCENE_TYPES: SceneType[] = ["outdoor", "indoor"];
export const STAGES: Stage[] = ["frames", "sfm", "train", "all"];

export const PRESETS: Record<Quality, { iters: number; maxFrames: number }> = {
  draft: { iters: 7_000, maxFrames: 150 },
  high: { iters: 30_000, maxFrames: 300 },
};

// Modal's published rates. Used only to show an estimate before spending —
// verify at modal.com/pricing.
const USD_PER_L4_SEC = 0.000222;
const USD_PER_CORE_SEC = 0.0000131;
const USD_PER_GIB_SEC = 0.00000222;

const SFM_CPU = 8;
const SFM_MEM_GIB = 16;
const TRAIN_MEM_GIB = 32;

/** Which stages a `--stage` value actually runs. */
export function stagesIn(stage: Stage): Exclude<Stage, "all">[] {
  return stage === "all" ? ["frames", "sfm", "train"] : [stage];
}

/** Only the training stage touches a GPU, and only it needs `--yes`. */
export function touchesGpu(stage: Stage): boolean {
  return stagesIn(stage).includes("train");
}

export interface EstimateLine {
  stage: string;
  resources: string;
  minutes: number;
  usd: number;
}

export interface Estimate {
  lines: EstimateLine[];
  total: number;
}

/**
 * Mirrors `_estimate()` in modal_app.py. `skip` holds stages the volume has
 * already cached — the CLI skips them, so the estimate must not bill for them.
 */
export function estimate(
  stage: Stage,
  quality: Quality,
  iters: number,
  skip: { frames?: boolean; sfm?: boolean } = {},
): Estimate {
  const wanted = stagesIn(stage);
  const lines: EstimateLine[] = [];

  if (wanted.includes("frames") && !skip.frames) {
    const secs = 180;
    lines.push({
      stage: "frames",
      resources: "CPU 4c / 8 GiB",
      minutes: secs / 60,
      usd: 4 * USD_PER_CORE_SEC * secs + 8 * USD_PER_GIB_SEC * secs,
    });
  }
  if (wanted.includes("sfm") && !skip.sfm) {
    const secs = 1200;
    lines.push({
      stage: "sfm",
      resources: `CPU ${SFM_CPU}c / ${SFM_MEM_GIB} GiB`,
      minutes: secs / 60,
      usd:
        SFM_CPU * USD_PER_CORE_SEC * secs + SFM_MEM_GIB * USD_PER_GIB_SEC * secs,
    });
  }
  if (wanted.includes("train")) {
    // ~1100 steps/min on an L4 at 1600px is the working assumption.
    const secs = (iters / 1100) * 60;
    lines.push({
      stage: "train",
      resources: `GPU L4 / ${TRAIN_MEM_GIB} GiB`,
      minutes: secs / 60,
      usd: secs * USD_PER_L4_SEC + TRAIN_MEM_GIB * USD_PER_GIB_SEC * secs,
    });
  }

  void quality;
  return { lines, total: lines.reduce((sum, l) => sum + l.usd, 0) };
}

/**
 * Volume path stem -> scene name, matching what `modal volume put` would make
 * of the filename. Lowercased and stripped to a safe set, because the name is
 * pasted into a Volume path and into CLI arguments.
 */
export function sceneNameFor(filename: string): string {
  const stem = filename.replace(/\.[^.]+$/, "");
  const name = stem
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return name || "scene";
}

export function formatUsd(usd: number): string {
  return `$${usd.toFixed(2)}`;
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB"];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(value >= 10 ? 0 : 1)} ${units[unit]}`;
}

export function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) return "—";
  const mins = Math.floor(seconds / 60);
  const secs = Math.round(seconds % 60);
  return mins > 0 ? `${mins}m ${secs}s` : `${secs}s`;
}
