"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import type { Job, JobInput } from "@/lib/jobs";
import type { VideoFile } from "@/lib/videos";

import { JobCard } from "./JobCard";
import { RunPanel } from "./RunPanel";
import { VideoCard } from "./VideoCard";
import styles from "./Dashboard.module.css";

interface VolumeOverview {
  volume: string;
  uploaded: string[];
  started: string[];
  error?: string;
}

export function Dashboard() {
  const [videos, setVideos] = useState<VideoFile[]>([]);
  const [videoDir, setVideoDir] = useState("");
  const [volume, setVolume] = useState<VolumeOverview | null>(null);
  const [jobs, setJobs] = useState<Job[]>([]);
  const [selected, setSelected] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    void (async () => {
      const [library, overview] = await Promise.all([
        fetch("/api/videos").then((res) => res.json()),
        fetch("/api/volume").then((res) => res.json()),
      ]);
      if (!live) return;
      setVideos(library.videos as VideoFile[]);
      setVideoDir(library.videoDir as string);
      setVolume(overview as VolumeOverview);
    })();
    return () => {
      live = false;
    };
  }, []);

  // One event stream carries every job's state and its log tail.
  useEffect(() => {
    const source = new EventSource("/api/jobs/events");
    source.onmessage = (event) => setJobs(JSON.parse(event.data).jobs as Job[]);
    return () => source.close();
  }, []);

  // A finished run changes what the Volume holds, which is what the badges and
  // the cost estimate are read off.
  const finished = jobs.filter((job) => job.finishedAt).length;
  useEffect(() => {
    if (finished === 0) return;
    let live = true;
    void (async () => {
      const overview = await fetch("/api/volume").then((res) => res.json());
      if (live) setVolume(overview as VolumeOverview);
    })();
    return () => {
      live = false;
    };
  }, [finished]);

  const selectedVideo = useMemo(
    () => videos.find((video) => video.file === selected) ?? null,
    [videos, selected],
  );

  const activeByScene = useMemo(() => {
    const map = new Map<string, Job>();
    for (const job of jobs) {
      if (job.status === "running" || job.status === "queued") {
        map.set(job.scene, job);
      }
    }
    return map;
  }, [jobs]);

  const start = useCallback(
    async (input: Omit<JobInput, "video">): Promise<string | null> => {
      if (!selectedVideo) return "no video selected";
      const response = await fetch("/api/jobs", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...input, video: selectedVideo.file }),
      });
      if (!response.ok) {
        const data = await response.json().catch(() => ({}));
        return (data as { error?: string }).error ?? "could not start the run";
      }
      return null;
    },
    [selectedVideo],
  );

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <div className={styles.brand}>
          <span className={styles.mark} aria-hidden>
            <svg width="26" height="26" viewBox="0 0 24 24" fill="none">
              <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="1.6" />
              <path
                d="M15.5 8.5 10.8 10.8 8.5 15.5l4.7-2.3z"
                fill="currentColor"
              />
            </svg>
          </span>
          <div>
            <h1 className={styles.title}>Splat Studio</h1>
            <p className={styles.tagline}>
              Turn a location video into a 3D Gaussian splat, on Modal.
            </p>
          </div>
        </div>

        <div className={styles.volumeChip}>
          <span className={styles.volumeName}>{volume?.volume ?? "gsplat-data"}</span>
          <span>
            {volume
              ? `${volume.uploaded.length} uploaded · ${volume.started.length} scenes`
              : "checking…"}
          </span>
        </div>
      </header>

      {volume?.error ? (
        <p className={`${styles.notice} ${styles.warning}`} style={{ marginBottom: 24 }}>
          {volume.error}
        </p>
      ) : null}

      <div className={styles.split}>
        <div className={styles.column}>
          <section>
            <h2 className={styles.sectionTitle}>
              Captures <span className={styles.count}>{videos.length}</span>
            </h2>
            {videos.length === 0 ? (
              <p className={styles.notice}>
                No clips yet. Drop a video into{" "}
                <span className={styles.path}>{videoDir}</span> and reload. A slow
                full orbit of 30–60 seconds reconstructs best.
              </p>
            ) : (
              <div className={styles.grid}>
                {videos.map((video) => (
                  <VideoCard
                    key={video.file}
                    video={video}
                    selected={video.file === selected}
                    uploaded={volume?.uploaded.includes(video.scene) ?? false}
                    hasScene={volume?.started.includes(video.scene) ?? false}
                    running={activeByScene.has(video.scene)}
                    onSelect={() => setSelected(video.file)}
                  />
                ))}
              </div>
            )}
          </section>

          <section>
            <h2 className={styles.sectionTitle}>
              Runs <span className={styles.count}>{jobs.length}</span>
            </h2>
            {jobs.length === 0 ? (
              <p className={styles.notice}>
                Nothing has run yet. Runs are kept in memory — restarting the
                dev server forgets them, but every stage output stays cached in
                the Volume.
              </p>
            ) : (
              <div className={styles.jobs}>
                {jobs.map((job, index) => (
                  <JobCard key={job.id} job={job} defaultOpen={index === 0} />
                ))}
              </div>
            )}
          </section>
        </div>

        <aside className={styles.rail}>
          <RunPanel
            video={selectedVideo}
            activeJob={
              selectedVideo ? activeByScene.get(selectedVideo.scene) ?? null : null
            }
            onStart={start}
          />
        </aside>
      </div>
    </main>
  );
}
