"use client";

import { useEffect, useRef, useState } from "react";

import type { Job, JobInput } from "@/lib/jobs";
import {
  estimate,
  formatUsd,
  PRESETS,
  touchesGpu,
  type Quality,
  type SceneType,
  type Stage,
} from "@/lib/pipeline";
import type { VideoFile } from "@/lib/videos";
import type { SceneStatus } from "@/lib/volume";

import { SegmentedControl } from "./SegmentedControl";
import styles from "./RunPanel.module.css";

interface Props {
  video: VideoFile | null;
  activeJob: Job | null;
  onStart: (input: Omit<JobInput, "video">) => Promise<string | null>;
}

export function RunPanel({ video, activeJob, onStart }: Props) {
  const [sceneType, setSceneType] = useState<SceneType>("outdoor");
  const [quality, setQuality] = useState<Quality>("draft");
  const [stage, setStage] = useState<Stage>("all");
  const [force, setForce] = useState(false);
  const [reupload, setReupload] = useState(false);

  const [fetched, setFetched] = useState<SceneStatus | null>(null);
  const [armed, setArmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const disarm = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Selecting another capture must not leave the previous run's confirmation
  // half-armed or its error on screen. Reconciled during render rather than in
  // an effect, so the panel never paints one video's state under another's name.
  const [shown, setShown] = useState(video?.file ?? null);
  if ((video?.file ?? null) !== shown) {
    setShown(video?.file ?? null);
    setArmed(false);
    setError(null);
  }

  // Cached stages come from the Volume, and they decide both what the CLI will
  // skip and what the estimate is allowed to charge for. Re-read when a run
  // ends, because that is exactly when the answer changes.
  useEffect(() => {
    if (!video) return;
    let live = true;
    void (async () => {
      try {
        const data = (await fetch(`/api/scenes/${video.scene}`).then((res) =>
          res.json(),
        )) as SceneStatus;
        if (live) setFetched(data);
      } catch {
        // Leave the chips reading "checking…" rather than claim nothing is cached.
      }
    })();
    return () => {
      live = false;
    };
  }, [video, activeJob?.status]);

  useEffect(() => () => {
    if (disarm.current) clearTimeout(disarm.current);
  }, []);

  if (!video) {
    return (
      <div className={styles.empty}>
        <span className={styles.emptyTitle}>Nothing selected</span>
        <span>Pick a capture to set up a run.</span>
      </div>
    );
  }

  // A fetch in flight when the selection changed would otherwise describe the
  // wrong scene; the chips fall back to "checking…" until this one lands.
  const status = fetched?.scene === video.scene ? fetched : null;

  const iters = PRESETS[quality].iters;
  const skip = force
    ? {}
    : { frames: (status?.frames ?? 0) > 0, sfm: status?.sfm === true };
  const cost = estimate(stage, quality, iters, skip);
  const gpu = touchesGpu(stage);
  const running = activeJob?.status === "running" || activeJob?.status === "queued";

  async function start() {
    if (gpu && !armed) {
      setArmed(true);
      if (disarm.current) clearTimeout(disarm.current);
      disarm.current = setTimeout(() => setArmed(false), 6_000);
      return;
    }
    setBusy(true);
    setError(null);
    const failure = await onStart({ sceneType, quality, stage, force, reupload });
    setBusy(false);
    setArmed(false);
    if (failure) setError(failure);
  }

  return (
    <div className={styles.panel}>
      <video
        key={video.file}
        className={styles.player}
        src={`/api/videos/${encodeURIComponent(video.file)}`}
        controls
        preload="metadata"
        playsInline
      />

      <div className={styles.head}>
        <h2 className={styles.title}>{video.scene}</h2>
        <span className={styles.subtitle}>
          gsplat-data:/raw/{video.scene}
          {video.file.slice(video.file.lastIndexOf("."))}
        </span>
      </div>

      <div className={styles.cached}>
        <span className={`${styles.chip} ${status?.frames ? styles.chipDone : ""}`}>
          {status ? (status.frames ? `${status.frames} frames` : "no frames") : "checking…"}
        </span>
        <span className={`${styles.chip} ${status?.sfm ? styles.chipDone : ""}`}>
          {status?.sfm ? "SfM done" : "no SfM"}
        </span>
        <span
          className={`${styles.chip} ${status?.plys.length ? styles.chipDone : ""}`}
        >
          {status?.plys.length
            ? `${status.plys.length} point cloud${status.plys.length > 1 ? "s" : ""}`
            : "no splat"}
        </span>
      </div>

      <div className={styles.controls}>
        <SegmentedControl<SceneType>
          label="Scene"
          value={sceneType}
          onChange={setSceneType}
          options={[
            { value: "outdoor", label: "Outdoor", hint: "seeds sky" },
            { value: "indoor", label: "Indoor", hint: "stricter match" },
          ]}
        />
        <SegmentedControl<Quality>
          label="Quality"
          value={quality}
          onChange={setQuality}
          options={[
            { value: "draft", label: "Draft", hint: "7k iters" },
            { value: "high", label: "High", hint: "30k iters" },
          ]}
        />
        <SegmentedControl<Stage>
          label="Stage"
          value={stage}
          onChange={setStage}
          options={[
            { value: "frames", label: "Frames" },
            { value: "sfm", label: "SfM" },
            { value: "train", label: "Train" },
            { value: "all", label: "All" },
          ]}
        />

        <div className={styles.toggles}>
          <label className={styles.toggle}>
            <input
              type="checkbox"
              checked={force}
              onChange={(event) => setForce(event.target.checked)}
            />
            <span className={styles.toggleText}>
              Redo cached stages
              <span className={styles.toggleHint}>
                Passes --force. Without it, a stage whose output is already in
                the Volume is skipped and costs nothing.
              </span>
            </span>
          </label>
          <label className={styles.toggle}>
            <input
              type="checkbox"
              checked={reupload}
              onChange={(event) => setReupload(event.target.checked)}
            />
            <span className={styles.toggleText}>
              Re-upload the clip
              <span className={styles.toggleHint}>
                Overwrites /raw. Only needed if you edited the file since the
                last run.
              </span>
            </span>
          </label>
        </div>
      </div>

      <div className={styles.estimate}>
        {cost.lines.map((line) => (
          <div className={styles.estimateRow} key={line.stage}>
            <span className={styles.estimateStage}>{line.stage}</span>
            <span>
              {line.resources} · ~{Math.round(line.minutes)} min
            </span>
            <span>~{formatUsd(line.usd)}</span>
          </div>
        ))}
        <div className={`${styles.estimateRow} ${styles.estimateTotal}`}>
          <span>total</span>
          <span>estimate, not a quote</span>
          <span>~{formatUsd(cost.total)}</span>
        </div>
      </div>

      {gpu ? (
        <p className={styles.gpuNote}>
          This run reaches the L4 training stage. SfM runs first and refuses to
          hand off unless at least 70% of frames register, so a bad capture
          fails before the GPU bills.
        </p>
      ) : null}

      {error ? <p className={styles.error}>{error}</p> : null}

      <button
        type="button"
        className={`${styles.start} ${armed ? styles.armed : ""}`}
        disabled={busy || running}
        onClick={start}
      >
        {running
          ? "A run is already going"
          : armed
            ? `Confirm — spend ~${formatUsd(cost.total)}`
            : `Start ${stage === "all" ? "full run" : stage}`}
      </button>

      <p className={styles.footnote}>
        Finished point clouds are standard INRIA 3DGS .ply — drop one on{" "}
        <a href="https://superspl.at/editor" target="_blank" rel="noreferrer">
          superspl.at/editor
        </a>{" "}
        to fly around it.
      </p>
    </div>
  );
}
