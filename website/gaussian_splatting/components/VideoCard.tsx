"use client";

import { useState } from "react";

import { formatBytes, formatDuration } from "@/lib/pipeline";
import type { VideoFile } from "@/lib/videos";

import styles from "./VideoCard.module.css";

interface Props {
  video: VideoFile;
  selected: boolean;
  uploaded: boolean;
  hasScene: boolean;
  running: boolean;
  onSelect: () => void;
}

export function VideoCard({
  video,
  selected,
  uploaded,
  hasScene,
  running,
  onSelect,
}: Props) {
  const [duration, setDuration] = useState<number | null>(null);

  return (
    <button
      type="button"
      className={`${styles.card} ${selected ? styles.selected : ""}`}
      aria-pressed={selected}
      onClick={onSelect}
    >
      <div className={styles.thumb}>
        {/* No thumbnailer and no ffmpeg on this side: the browser decodes the
            first second itself, which is all a poster frame ever needed. */}
        <video
          src={`/api/videos/${encodeURIComponent(video.file)}#t=0.5`}
          preload="metadata"
          muted
          playsInline
          onLoadedMetadata={(event) =>
            setDuration(event.currentTarget.duration)
          }
        />
        <div className={styles.scrim} />
        <div className={styles.badges}>
          {running ? <span className={styles.badge}>running</span> : null}
          {hasScene ? <span className={`${styles.badge} ${styles.badgeReady}`}>splat</span> : null}
          {uploaded && !hasScene ? <span className={styles.badge}>uploaded</span> : null}
        </div>
      </div>

      <div className={styles.body}>
        <span className={styles.name}>{video.file}</span>
        <span className={styles.meta}>
          <span className={styles.scene}>{video.scene}</span>
          <span>·</span>
          <span>{formatBytes(video.sizeBytes)}</span>
          {duration ? (
            <>
              <span>·</span>
              <span>{formatDuration(duration)}</span>
            </>
          ) : null}
        </span>
      </div>
    </button>
  );
}
