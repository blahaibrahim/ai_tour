"use client";

import Image from "next/image";
import { useCallback, useEffect, useState, useSyncExternalStore } from "react";

import { Overview } from "./Overview";
import { Studio } from "./Studio";
import styles from "./Dashboard.module.css";

const TABS = [
  { id: "overview", label: "Overview" },
  { id: "studio", label: "Studio" },
] as const;

type Tab = (typeof TABS)[number]["id"];

export interface VolumeOverview {
  volume: string;
  uploaded: string[];
  started: string[];
  error?: string;
}

function subscribeToHash(onChange: () => void) {
  window.addEventListener("hashchange", onChange);
  return () => window.removeEventListener("hashchange", onChange);
}

/**
 * The shell: the brand, the Volume chip, and which of the two views is on.
 *
 * The Volume overview lives here rather than in the Studio because the chip in
 * the header shows it on every tab, and it costs two `modal volume ls` calls —
 * one fetch, passed down, instead of one per tab switch.
 */
export function Dashboard() {
  // The selection lives in the URL fragment rather than in state, so a view can
  // be linked to and reloaded into. Read through useSyncExternalStore because
  // `location` does not exist during the server render.
  const hash = useSyncExternalStore(
    subscribeToHash,
    () => window.location.hash.slice(1),
    () => "",
  );

  // `#studio/16/<poi-id>/<clip>/<ply>` — the tab, then whatever that tab wants
  // to remember. Segments are encoded because a clip is a filename and can
  // hold spaces and other characters a bare fragment would mangle.
  const segments = hash.split("/").filter(Boolean).map(decodeURIComponent);
  const tab: Tab = TABS.some((entry) => entry.id === segments[0])
    ? (segments[0] as Tab)
    : "overview";

  const [volume, setVolume] = useState<VolumeOverview | null>(null);
  // Bumped when a run finishes, which is what makes the chip re-read the
  // Volume without the Studio reaching into this component's state.
  const [generation, setGeneration] = useState(0);
  const invalidateVolume = useCallback(() => setGeneration((n) => n + 1), []);

  useEffect(() => {
    let live = true;
    void (async () => {
      const overview = await fetch("/api/volume").then((res) => res.json());
      if (live) setVolume(overview as VolumeOverview);
    })();
    return () => {
      live = false;
    };
  }, [generation]);

  const navigate = useCallback((next: string[]) => {
    window.location.hash = ["studio", ...next].map(encodeURIComponent).join("/");
  }, []);

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <div className={styles.brand}>
          <Image
            className={styles.mark}
            src="/logo.png"
            alt=""
            width={52}
            height={52}
            priority
          />
          <div>
            <h1 className={styles.title}>Massar Studio</h1>
            <p className={styles.tagline}>
              The catalogue, what explorers captured in it, and the splats
              trained from that footage.
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

      <nav className={styles.tabs} aria-label="Views">
        {TABS.map((entry) => (
          <a
            key={entry.id}
            href={`#${entry.id}`}
            className={`${styles.tab} ${tab === entry.id ? styles.tabActive : ""}`}
            aria-current={tab === entry.id ? "page" : undefined}
          >
            {entry.label}
          </a>
        ))}
      </nav>

      {volume?.error ? (
        <p className={`${styles.notice} ${styles.warning}`} style={{ marginBottom: 24 }}>
          {volume.error}
        </p>
      ) : null}

      {tab === "overview" ? <Overview /> : null}
      {tab === "studio" ? (
        <Studio
          path={segments.slice(1)}
          volume={volume}
          onVolumeChange={invalidateVolume}
          onNavigate={navigate}
        />
      ) : null}
    </main>
  );
}
