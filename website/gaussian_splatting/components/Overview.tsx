"use client";

import { useEffect, useState } from "react";

import type { Analytics } from "@/lib/analytics";
import { formatBytes } from "@/lib/pipeline";

import {
  BarList,
  Card,
  Funnel,
  Hero,
  Sparkline,
  StatusList,
  Tile,
  Tiles,
} from "./Charts";
import styles from "./Overview.module.css";

type Payload = Analytics & { hint?: string };

/**
 * What the project looks like right now: the catalogue explorers browse, what
 * they have captured in it, and how far those captures have got through the
 * splat pipeline.
 *
 * Read-only, and refreshed on mount rather than polled — none of these numbers
 * move on a timescale where a live feed would tell you anything the Runs tab
 * doesn't already stream.
 */
export function Overview() {
  const [data, setData] = useState<Payload | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    void (async () => {
      try {
        const response = await fetch("/api/analytics");
        const payload = (await response.json()) as Payload;
        if (live) setData(payload);
      } catch (err) {
        if (live) setError((err as Error).message);
      }
    })();
    return () => {
      live = false;
    };
  }, []);

  if (error) return <p className={styles.notice}>could not load: {error}</p>;
  if (!data) return <p className={styles.loading}>reading the project…</p>;

  const { totals, splat } = data;

  return (
    <div className={styles.overview}>
      {data.hint ? <p className={styles.notice}>{data.hint}</p> : null}
      {data.errors.length > 0 ? (
        <div className={styles.notice}>
          Some numbers are missing — these reads failed:
          <ul className={styles.noticeList}>
            {data.errors.map((message) => (
              <li key={message}>{message}</li>
            ))}
          </ul>
        </div>
      ) : null}

      <div className={styles.lead}>
        <Hero
          value={totals.explorers}
          label={`explorers signed in · ${totals.newExplorers30d} joined in the last 30 days`}
        />
        <Tiles>
          <Tile
            label="Stops on the map"
            value={totals.pois}
            hint={`${totals.publishedPois} published · ${totals.cities} cities`}
          />
          <Tile
            label="Routes generated"
            value={totals.routes}
            hint={`${totals.routeStops} stops · ${totals.routesCompleted} walked to the end`}
          />
          <Tile
            label="Captures uploaded"
            value={totals.captures}
            hint={`${totals.models} finished 3D models`}
          />
          <Tile
            label="Points earned"
            value={totals.points}
            hint={`${totals.savedLocations} places saved`}
          />
        </Tiles>
      </div>

      <div className={styles.grid}>
        <Card
          title="Splat pipeline"
          note={
            splat.started > splat.inspected
              ? `first ${splat.inspected} of ${splat.started} scenes`
              : splat.volume
          }
        >
          <Funnel
            steps={[
              { label: "clips on this machine", value: splat.clips },
              { label: "uploaded to the Volume", value: splat.uploaded },
              { label: "frames extracted", value: splat.framed },
              { label: "SfM reconstructed", value: splat.reconstructed },
              { label: "splat trained", value: splat.trained },
            ]}
            emptyText={
              splat.error
                ? splat.error
                : "no clips yet — drop one in videos/ and start a run."
            }
          />
          <p className={styles.footnote}>
            SfM is the gate: a capture that fails to reconstruct costs CPU
            minutes, not L4 minutes. A drop between those two rows is footage,
            not infrastructure.
          </p>
        </Card>

        <Card title="Captures per week" note="last 12 weeks">
          <Sparkline
            points={data.capturesByWeek}
            emptyText="not enough history to plot yet"
          />
        </Card>

        <Card title="Stops by category">
          <BarList rows={data.poisByCategory} />
        </Card>

        <Card title="Stops by city">
          <BarList rows={data.poisByCity} />
        </Card>

        <Card title="Captures by kind" note="what explorers made">
          <BarList
            rows={data.artifactsByKind}
            emptyText="nothing captured in the app yet"
          />
        </Card>

        <Card
          title="3D model jobs"
          note={
            data.modelTurnaroundMinutes === null
              ? undefined
              : `median ${data.modelTurnaroundMinutes.toFixed(1)} min`
          }
        >
          <StatusList rows={data.modelJobsByStatus} />
          <p className={styles.footnote}>
            {data.gpuSeconds > 0
              ? `${Math.round(data.gpuSeconds).toLocaleString("en-US")} GPU-seconds billed across every job.`
              : "No GPU seconds recorded yet."}
          </p>
        </Card>

        <Card title="Route jobs">
          <StatusList rows={data.routeJobsByStatus} emptyText="no route jobs yet" />
        </Card>

        <Card title="Storage" note="private buckets">
          {data.storage.length === 0 ? (
            <p className={styles.footnote}>
              Nothing to show. Reading object sizes needs the <code>storage</code>{" "}
              schema exposed to the Data API (Project Settings &gt; API); without
              it this card stays empty and nothing else is affected.
            </p>
          ) : (
            <table className={styles.table}>
              <thead>
                <tr>
                  <th>Bucket</th>
                  <th className={styles.numeric}>Objects</th>
                  <th className={styles.numeric}>Size</th>
                </tr>
              </thead>
              <tbody>
                {data.storage.map((bucket) => (
                  <tr key={bucket.bucket}>
                    <td className={styles.bucket}>{bucket.bucket}</td>
                    <td className={styles.numeric}>{bucket.objects}</td>
                    <td className={styles.numeric}>{formatBytes(bucket.bytes)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Card>

        <Card title="Catalogue health">
          <Tiles>
            <Tile
              label="Stops with a photo"
              value={`${totals.pois === 0 ? 0 : Math.round((totals.poisWithPhoto / totals.pois) * 100)}%`}
              hint={`${totals.poisWithPhoto} of ${totals.pois}`}
            />
            <Tile
              label="Devices reachable"
              value={totals.pushTokens}
              hint="registered push tokens"
            />
          </Tiles>
          <p className={styles.footnote}>Review state of every stop:</p>
          <StatusList rows={data.poisByStatus} emptyText="no stops yet" />
        </Card>
      </div>
    </div>
  );
}
