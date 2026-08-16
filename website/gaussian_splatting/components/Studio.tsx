"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import type { Atlas as AtlasData, AtlasPoi, PoiDetail } from "@/lib/atlas";
import type { Job, JobInput } from "@/lib/jobs";
import type { VideoFile } from "@/lib/videos";
import type { SceneStatus } from "@/lib/volume";

import { AlgeriaMap } from "./AlgeriaMap";
import { JobCard } from "./JobCard";
import { RunPanel } from "./RunPanel";
import { SplatCanvas } from "./SplatCanvas";
import { VideoCard } from "./VideoCard";
import styles from "./Studio.module.css";

/**
 * The working view: where a capture is on one side, what splatting has made of
 * it on the other.
 *
 * Left is the drill-down — wilaya, then the stops in it, then the footage
 * recorded at a stop. Right is everything about the one clip selected there:
 * the player, which stages are already cached, the cost of the run you are
 * about to start, the live log of the run itself, and the splat it produced.
 *
 * These used to be two tabs, which meant picking a clip on a map and then
 * losing the map to go and run it. One selection now drives both halves, and
 * that selection lives in the URL so it can be linked to:
 * `#studio/16/<poi-id>/<clip>/<ply>`.
 */

type Payload = AtlasData & { hint?: string };

export function Studio({
  path,
  volume,
  onVolumeChange,
  onNavigate,
}: {
  path: string[];
  volume: { uploaded: string[]; started: string[] } | null;
  onVolumeChange: () => void;
  onNavigate: (next: string[]) => void;
}) {
  const wilayaCode = path[0] ?? null;
  const poiId = path[1] ?? null;
  const clipFile = path[2] ?? null;
  const plyName = path[3] ?? null;

  const [atlas, setAtlas] = useState<Payload | null>(null);
  const [videos, setVideos] = useState<VideoFile[]>([]);
  // Tagged with the stop it belongs to, so a detail still in flight for the
  // previously selected stop can never be rendered under the new one.
  const [loaded, setLoaded] = useState<{ id: string; detail: PoiDetail } | null>(
    null,
  );
  const [jobs, setJobs] = useState<Job[]>([]);
  const [scenes, setScenes] = useState<Record<string, SceneStatus>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  // Bumped whenever an assignment changes; every read below depends on it.
  const [generation, setGeneration] = useState(0);

  const detail = loaded?.id === poiId ? loaded.detail : null;

  useEffect(() => {
    let live = true;
    void (async () => {
      const [map, library] = await Promise.all([
        fetch("/api/atlas").then((res) => res.json()),
        fetch("/api/videos").then((res) => res.json()),
      ]);
      if (!live) return;
      setAtlas(map as Payload);
      setVideos(library.videos as VideoFile[]);
    })();
    return () => {
      live = false;
    };
  }, [generation]);

  // Stop details are per-POI and involve signing storage URLs, so they are
  // fetched on selection rather than shipped with the whole atlas.
  useEffect(() => {
    if (!poiId) return;
    let live = true;
    void (async () => {
      const response = await fetch(`/api/atlas/pois/${poiId}`);
      const payload = (await response.json()) as PoiDetail;
      if (live) setLoaded({ id: poiId, detail: payload });
    })();
    return () => {
      live = false;
    };
  }, [poiId, generation]);

  // One event stream carries every job's state and its log tail.
  useEffect(() => {
    const source = new EventSource("/api/jobs/events");
    source.onmessage = (event) => setJobs(JSON.parse(event.data).jobs as Job[]);
    return () => source.close();
  }, []);

  const poi = useMemo(
    () => (atlas?.pois ?? []).find((entry) => entry.id === poiId) ?? null,
    [atlas, poiId],
  );

  const clip = useMemo(
    () => videos.find((video) => video.file === clipFile) ?? null,
    [videos, clipFile],
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

  // Which point clouds the selected scene has, re-read on selection and again
  // whenever a run ends — the two moments the answer can change. The run panel
  // reads the same endpoint for its own chips; this copy is what the splat
  // card lists.
  const finished = jobs.filter((job) => job.finishedAt).length;
  useEffect(() => {
    if (!clip) return;
    let live = true;
    void (async () => {
      const response = await fetch(`/api/scenes/${clip.scene}`);
      if (!response.ok) return;
      const status = (await response.json()) as SceneStatus;
      if (live) setScenes((current) => ({ ...current, [clip.scene]: status }));
    })();
    return () => {
      live = false;
    };
  }, [clip, finished]);

  // A finished run also changes what the Volume holds, which is what the
  // header chip and the capture badges are read off.
  useEffect(() => {
    if (finished > 0) onVolumeChange();
  }, [finished, onVolumeChange]);

  const go = useCallback(
    (next: (string | null)[]) =>
      onNavigate(next.filter((part): part is string => Boolean(part))),
    [onNavigate],
  );

  const attach = useCallback(
    async (kind: "clips" | "artifacts", key: string, target: string | null) => {
      setError(null);
      const response = await fetch("/api/assignments", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ kind, key, poiId: target }),
      });
      if (!response.ok) {
        const body = (await response.json().catch(() => ({}))) as { error?: string };
        setError(body.error ?? "could not save that");
        return;
      }
      setGeneration((n) => n + 1);
    },
    [],
  );

  const startRun = useCallback(
    async (input: Omit<JobInput, "video">): Promise<string | null> => {
      if (!clip) return "no clip selected";
      const response = await fetch("/api/jobs", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...input, video: clip.file }),
      });
      if (!response.ok) {
        const data = (await response.json().catch(() => ({}))) as { error?: string };
        return data.error ?? "could not start the run";
      }
      return null;
    },
    [clip],
  );

  const fetchSplat = useCallback(
    async (scene: string, name: string) => {
      setBusy(`${scene}/${name}`);
      setError(null);
      try {
        const response = await fetch(`/api/scenes/${scene}/splat/${name}`, {
          method: "POST",
        });
        if (!response.ok) {
          const body = (await response.json().catch(() => ({}))) as { error?: string };
          throw new Error(body.error ?? "could not fetch it");
        }
        const status = await fetch(`/api/scenes/${scene}`);
        if (status.ok) {
          const fresh = (await status.json()) as SceneStatus;
          setScenes((current) => ({ ...current, [scene]: fresh }));
        }
        go([wilayaCode, poiId, clipFile, name]);
      } catch (err) {
        setError((err as Error).message);
      } finally {
        setBusy(null);
      }
    },
    [go, wilayaCode, poiId, clipFile],
  );

  if (!atlas) return <p className={styles.loading}>reading the map…</p>;

  const poisInWilaya = atlas.pois.filter(
    (entry) => wilayaCode !== null && entry.wilayaCode === wilayaCode,
  );
  const wilayaName =
    atlas.wilayas.find((entry) => entry.code === wilayaCode)?.name ?? null;
  const unattached = videos.filter((video) =>
    atlas.unassignedClips.includes(video.file),
  );
  const scene = clip ? scenes[clip.scene] : undefined;

  // A run started here and then navigated away from should still be findable.
  const elsewhere = [...activeByScene.values()].find(
    (job) => job.video !== clipFile,
  );

  const cardFor = (video: VideoFile) => (
    <VideoCard
      key={video.file}
      video={video}
      selected={video.file === clipFile}
      uploaded={volume?.uploaded.includes(video.scene) ?? false}
      hasScene={volume?.started.includes(video.scene) ?? false}
      running={activeByScene.has(video.scene)}
      onSelect={() => go([wilayaCode, poiId, video.file])}
    />
  );

  return (
    <div className={styles.studio}>
      <div className={styles.left}>
        {atlas.hint ? <p className={styles.notice}>{atlas.hint}</p> : null}

        <section className={styles.card}>
          <h2 className={styles.cardTitle}>
            Algeria
            <span className={styles.cardNote}>
              {atlas.pois.length} stops · click a wilaya
            </span>
          </h2>
          <AlgeriaMap
            wilayas={atlas.wilayas}
            selected={wilayaCode}
            onSelect={(code) => go([code])}
          />
        </section>

        <section className={styles.card}>
          <h2 className={styles.cardTitle}>
            {wilayaName ?? "Stops"}
            <span className={styles.cardNote}>
              {wilayaCode === null
                ? "pick a wilaya above"
                : `${poisInWilaya.length} stops`}
            </span>
          </h2>

          {wilayaCode === null ? (
            <p className={styles.empty}>
              Shaded wilayas hold stops. The three seeded cities — Algiers, Oran
              and Constantine — are the only ones with a catalogue so far.
            </p>
          ) : poisInWilaya.length === 0 ? (
            <p className={styles.empty}>
              No stops here yet. {wilayaName} has nothing in the <code>pois</code>{" "}
              table.
            </p>
          ) : (
            <div className={styles.pois}>
              {poisInWilaya.map((entry) => (
                <PoiRow
                  key={entry.id}
                  poi={entry}
                  selected={entry.id === poiId}
                  onSelect={() => go([wilayaCode, entry.id])}
                />
              ))}
            </div>
          )}
        </section>

        <section className={styles.card}>
          <h2 className={styles.cardTitle}>
            {poi ? `Footage at ${poi.name}` : "Footage"}
            <span className={styles.cardNote}>
              {poi ? "pick a clip to run" : "pick a stop first"}
            </span>
          </h2>

          {!poi ? (
            <p className={styles.empty}>
              Select a stop to see what was recorded there.
            </p>
          ) : !detail ? (
            <p className={styles.empty}>loading…</p>
          ) : detail.clips.length === 0 ? (
            <p className={styles.empty}>
              No clips attached to this stop yet. Attach one from{" "}
              <em>Not attached</em> below, or drop a new capture into{" "}
              <code>videos/</code> and reload.
            </p>
          ) : (
            <>
              <div className={styles.clips}>{detail.clips.map(cardFor)}</div>
              {/* The only way to move a clip to a different stop: detach it
                  here, select the other stop, attach it there. */}
              {clip && detail.clips.some((entry) => entry.file === clip.file) ? (
                <div className={styles.actions}>
                  <button
                    type="button"
                    className={`${styles.button} ${styles.buttonQuiet}`}
                    onClick={() => void attach("clips", clip.file, null)}
                  >
                    Detach {clip.file}
                  </button>
                </div>
              ) : null}
            </>
          )}

          {detail && detail.captures.length > 0 ? (
            <>
              <h3 className={styles.subTitle}>From the app</h3>
              <div className={styles.captures}>
                {detail.captures.map((capture) => (
                  <article key={capture.id} className={styles.capture}>
                    {capture.kind === "video" && capture.imageUrl ? (
                      <video
                        className={styles.captureFrame}
                        src={capture.imageUrl}
                        preload="metadata"
                        controls
                        playsInline
                      />
                    ) : capture.imageUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        className={styles.captureFrame}
                        src={capture.imageUrl}
                        alt={capture.title}
                      />
                    ) : (
                      <div className={styles.captureFrame} />
                    )}
                    <div className={styles.captureBody}>
                      <span className={styles.captureName}>{capture.title}</span>
                      <span className={styles.captureMeta}>
                        {capture.kind} ·{" "}
                        {new Date(capture.capturedAt).toLocaleDateString()}
                      </span>
                      <div className={styles.actions}>
                        {capture.modelUrl ? (
                          <a
                            className={`${styles.button} ${styles.buttonQuiet}`}
                            href={capture.modelUrl}
                            download
                          >
                            .glb
                          </a>
                        ) : null}
                        <button
                          type="button"
                          className={`${styles.button} ${styles.buttonQuiet}`}
                          onClick={() => void attach("artifacts", capture.id, null)}
                        >
                          detach
                        </button>
                      </div>
                    </div>
                  </article>
                ))}
              </div>
              <p className={styles.footnote}>
                Photos and Hunyuan models from the phone. They are not splat
                input — a splat needs a video orbit.
              </p>
            </>
          ) : null}

          {unattached.length > 0 ? (
            <>
              <h3 className={styles.subTitle}>
                Not attached
                <span className={styles.cardNote}>
                  {unattached.length} clip{unattached.length === 1 ? "" : "s"} in
                  videos/
                </span>
              </h3>
              <div className={styles.clips}>{unattached.map(cardFor)}</div>
              {poi && clip && atlas.unassignedClips.includes(clip.file) ? (
                <div className={styles.actions}>
                  <button
                    type="button"
                    className={styles.button}
                    onClick={() => void attach("clips", clip.file, poi.id)}
                  >
                    Attach {clip.file} to {poi.name}
                  </button>
                </div>
              ) : null}
            </>
          ) : null}

          <p className={styles.footnote}>
            The clip-to-stop link lives in <code>videos/assignments.json</code>,
            not in the database: <code>artifacts.location_id</code> points at the
            empty <code>locations</code> catalogue, while the map runs on{" "}
            <code>pois</code>. An <code>artifacts.poi_id</code> column is the
            durable fix, and it belongs in a migration with the app change that
            writes it.
          </p>
          {error ? <p className={styles.error}>{error}</p> : null}
        </section>
      </div>

      <div className={styles.right}>
        {elsewhere ? (
          <button
            type="button"
            className={styles.jump}
            onClick={() => {
              const owner = atlas.clipOwners[elsewhere.video];
              const target = atlas.pois.find((entry) => entry.id === owner);
              go([target?.wilayaCode ?? wilayaCode, owner ?? null, elsewhere.video]);
            }}
          >
            <span className={styles.jumpDot} />
            {elsewhere.scene} is {elsewhere.status} — jump to it
          </button>
        ) : null}

        <section className={styles.card}>
          <RunPanel
            video={clip}
            activeJob={clip ? activeByScene.get(clip.scene) ?? null : null}
            onStart={startRun}
          />
        </section>

        {clip ? (
          <SplatCard
            scene={scene}
            sceneName={clip.scene}
            viewingPly={plyName}
            busy={busy}
            onView={(name) => go([wilayaCode, poiId, clipFile, name])}
            onFetch={(name) => void fetchSplat(clip.scene, name)}
          />
        ) : null}

        {clip ? <SceneRuns jobs={jobs} scene={clip.scene} /> : null}
      </div>
    </div>
  );
}

function PoiRow({
  poi,
  selected,
  onSelect,
}: {
  poi: AtlasPoi;
  selected: boolean;
  onSelect: () => void;
}) {
  const media = poi.counts.clips + poi.counts.captures + poi.counts.models;
  return (
    <button
      type="button"
      className={`${styles.poi} ${selected ? styles.poiSelected : ""}`}
      aria-pressed={selected}
      onClick={onSelect}
    >
      <span className={styles.poiBody}>
        <span className={styles.poiName}>{poi.name}</span>
        <span className={styles.poiMeta}>
          {poi.categoryLabel} · {poi.city}
        </span>
      </span>
      <span className={styles.tags}>
        {poi.counts.clips > 0 ? (
          <span className={`${styles.tag} ${styles.tagStrong}`}>
            {poi.counts.clips} clip{poi.counts.clips === 1 ? "" : "s"}
          </span>
        ) : null}
        {poi.counts.captures > 0 ? (
          <span className={styles.tag}>{poi.counts.captures} captures</span>
        ) : null}
        {media === 0 ? <span className={styles.tag}>—</span> : null}
      </span>
    </button>
  );
}

/**
 * The splat half. One point cloud at a time: a `.ply` is tens to hundreds of MB
 * and holds a million gaussians, so the viewer renders the one you asked for.
 */
function SplatCard({
  scene,
  sceneName,
  viewingPly,
  busy,
  onView,
  onFetch,
}: {
  scene: SceneStatus | undefined;
  sceneName: string;
  viewingPly: string | null;
  busy: string | null;
  onView: (name: string | null) => void;
  onFetch: (name: string) => void;
}) {
  const plys = scene?.plys ?? [];

  return (
    <section className={styles.card}>
      <h2 className={styles.cardTitle}>
        Gaussian splat
        <span className={styles.cardNote}>
          {plys.length} point cloud{plys.length === 1 ? "" : "s"}
        </span>
      </h2>

      {viewingPly ? (
        <SplatCanvas
          key={`${sceneName}/${viewingPly}`}
          url={`/api/scenes/${sceneName}/splat/${viewingPly}`}
        />
      ) : null}

      {plys.length === 0 ? (
        <p className={styles.empty}>
          Nothing trained from this clip yet. Run <code>All</code> above — or{" "}
          <code>SfM</code> first, which is the gate and costs CPU minutes rather
          than GPU minutes.
        </p>
      ) : (
        <div className={styles.actions}>
          {plys.map((ply) => {
            const isViewing = viewingPly === ply.name;
            return ply.cached ? (
              <button
                key={ply.name}
                type="button"
                className={`${styles.button} ${isViewing ? "" : styles.buttonQuiet}`}
                onClick={() => onView(isViewing ? null : ply.name)}
              >
                {isViewing ? "hide" : "view"} {ply.name} · {ply.size}
              </button>
            ) : (
              <button
                key={ply.name}
                type="button"
                className={`${styles.button} ${styles.buttonQuiet}`}
                disabled={busy !== null}
                onClick={() => onFetch(ply.name)}
              >
                {busy === `${sceneName}/${ply.name}`
                  ? `fetching ${ply.name}…`
                  : `fetch ${ply.name} · ${ply.size}`}
              </button>
            );
          })}
        </div>
      )}

      <p className={styles.footnote}>
        Each gaussian is drawn as a screen-space disc, sized by its own scale and
        blended back to front. That is the cheap half of splatting — the real
        rasteriser projects each covariance to an oriented ellipse, so flat
        surfaces look flat rather than stippled. For the full render, drop the
        fetched <code>.ply</code> on{" "}
        <a href="https://superspl.at/editor" target="_blank" rel="noreferrer">
          superspl.at/editor
        </a>
        .
      </p>
    </section>
  );
}

/** Every run this scene has had, newest first, with its streamed log. */
function SceneRuns({ jobs, scene }: { jobs: Job[]; scene: string }) {
  const mine = jobs.filter((job) => job.scene === scene);
  if (mine.length === 0) return null;

  return (
    <section className={styles.card}>
      <h2 className={styles.cardTitle}>
        Runs
        <span className={styles.cardNote}>{scene}</span>
      </h2>
      <div className={styles.jobs}>
        {mine.map((job, index) => (
          <JobCard key={job.id} job={job} defaultOpen={index === 0} />
        ))}
      </div>
    </section>
  );
}
