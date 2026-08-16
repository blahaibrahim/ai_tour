import type { ReactNode } from "react";

import styles from "./Charts.module.css";

/**
 * The chart vocabulary this dashboard draws with.
 *
 * Every number on the overview answers "how much" — how many POIs in a
 * category, how many captures a week, how far a scene got through the
 * pipeline. That is *magnitude*, so it takes one hue with more-is-darker, and
 * there is deliberately no categorical palette here: a rainbow of category
 * colors would spend the identity channel re-encoding what bar length already
 * shows.
 *
 * Every value is directly labelled, which is also the accessibility relief
 * channel — nothing on this page is readable only by comparing two fills.
 */

export function Card({
  title,
  note,
  children,
}: {
  title: string;
  note?: string;
  children: ReactNode;
}) {
  return (
    <section className={styles.card}>
      <h2 className={styles.cardTitle}>
        {title}
        {note ? <span className={styles.cardNote}>{note}</span> : null}
      </h2>
      {children}
    </section>
  );
}

/** 1,284 / 12.9K / 3.4M — a stat tile is unreadable at seven digits. */
export function compact(value: number): string {
  if (!Number.isFinite(value)) return "—";
  if (Math.abs(value) < 10_000) return value.toLocaleString("en-US");
  if (Math.abs(value) < 1_000_000) return `${(value / 1_000).toFixed(1)}K`;
  return `${(value / 1_000_000).toFixed(1)}M`;
}

/** The one number the view leads with. Exactly one per page. */
export function Hero({
  value,
  label,
}: {
  value: number | string;
  label: string;
}) {
  return (
    <div className={styles.hero}>
      <span className={styles.heroValue}>
        {typeof value === "number" ? compact(value) : value}
      </span>
      <span className={styles.heroLabel}>{label}</span>
    </div>
  );
}

export function Tiles({ children }: { children: ReactNode }) {
  return <div className={styles.tiles}>{children}</div>;
}

export function Tile({
  label,
  value,
  hint,
}: {
  label: string;
  value: number | string;
  hint?: string;
}) {
  return (
    <div className={styles.tile}>
      <span className={styles.tileLabel}>{label}</span>
      <span className={styles.tileValue}>
        {typeof value === "number" ? compact(value) : value}
      </span>
      {hint ? <span className={styles.tileHint}>{hint}</span> : null}
    </div>
  );
}

export interface Slice {
  label: string;
  value: number;
}

/**
 * Horizontal bars for a handful of named quantities.
 *
 * Horizontal because the labels are words ("historical monument"), and a
 * column chart would either rotate them or truncate them. Every bar carries
 * its value at the tip, so the chart never depends on reading a length.
 */
export function BarList({
  rows,
  suffix,
  emptyText = "nothing to show yet",
}: {
  rows: Slice[];
  suffix?: string;
  emptyText?: string;
}) {
  if (rows.length === 0) {
    return <p className={styles.empty}>{emptyText}</p>;
  }
  const max = Math.max(...rows.map((row) => row.value), 1);

  return (
    <div className={styles.bars}>
      {rows.map((row) => (
        <div key={row.label} className={styles.barRow}>
          <span className={styles.barLabel} title={row.label}>
            {row.label}
          </span>
          <span className={styles.barTrack}>
            <span
              className={styles.barFill}
              style={{ width: `${(row.value / max) * 100}%` }}
            />
          </span>
          <span className={styles.barValue}>
            {row.value.toLocaleString("en-US")}
            {suffix ? ` ${suffix}` : ""}
          </span>
        </div>
      ))}
    </div>
  );
}

/**
 * The pipeline funnel: an ordered sequence, so it takes an ordered ramp rather
 * than four unrelated hues. Reading light-to-dark left of the eye tells you
 * which stage you are looking at without consulting a legend.
 */
export function Funnel({
  steps,
  emptyText,
}: {
  steps: { label: string; value: number }[];
  emptyText: string;
}) {
  const max = Math.max(...steps.map((step) => step.value), 0);
  if (max === 0) return <p className={styles.empty}>{emptyText}</p>;

  return (
    <div className={styles.funnel}>
      {steps.map((step, index) => {
        const share = step.value / max;
        // A label only goes inside the bar when the bar is long enough to hold
        // it with padding — otherwise it rides outside, never clipped.
        const inside = share > 0.34;
        return (
          <div key={step.label} className={styles.funnelRow}>
            <div className={styles.funnelTrack}>
              <span
                className={styles.funnelBar}
                style={{
                  width: `${Math.max(share * 100, 2)}%`,
                  background: `var(--data-${Math.min(index + 1, 5)})`,
                }}
              >
                {inside ? step.label : null}
              </span>
              {inside ? null : (
                <span className={styles.funnelOutside}>{step.label}</span>
              )}
            </div>
            <span className={styles.funnelCount}>
              {step.value.toLocaleString("en-US")}
              {index > 0 && steps[index - 1].value > step.value ? (
                <span className={styles.funnelDrop}>
                  −{steps[index - 1].value - step.value}
                </span>
              ) : null}
            </span>
          </div>
        );
      })}
    </div>
  );
}

/**
 * Job states. These are *status*, not series: they carry reserved meaning, so
 * they wear the status tokens and never the data hue — and each one ships with
 * a glyph and a word, so the state never depends on the color alone.
 */
const TONES: Record<string, { tone: string; icon: string }> = {
  succeeded: { tone: "good", icon: "✓" },
  accepted: { tone: "good", icon: "✓" },
  completed: { tone: "good", icon: "✓" },
  published: { tone: "good", icon: "✓" },
  processing: { tone: "warn", icon: "◐" },
  uploading: { tone: "warn", icon: "◐" },
  in_progress: { tone: "warn", icon: "◐" },
  failed: { tone: "bad", icon: "✕" },
  cancelled: { tone: "bad", icon: "✕" },
  abandoned: { tone: "bad", icon: "✕" },
};

export function StatusList({
  rows,
  emptyText = "no jobs yet",
}: {
  rows: Slice[];
  emptyText?: string;
}) {
  if (rows.length === 0) return <p className={styles.empty}>{emptyText}</p>;

  return (
    <div className={styles.statuses}>
      {rows.map((row) => {
        const { tone, icon } = TONES[row.label] ?? { tone: "idle", icon: "•" };
        return (
          <div key={row.label} className={styles.statusRow}>
            <span
              className={`${styles.statusIcon} ${styles[tone]}`}
              aria-hidden
            >
              {icon}
            </span>
            <span className={styles.statusLabel}>{row.label.replace(/_/g, " ")}</span>
            <span className={`${styles.statusCount} ${styles[tone]}`}>
              {row.value}
            </span>
          </div>
        );
      })}
    </div>
  );
}

/**
 * One series over time. Area at ~10% under a 2px line, with the current value
 * marked and labelled — no number on every point, because a dozen labels in a
 * 90px band is noise nobody reads.
 */
export function Sparkline({
  points,
  emptyText,
}: {
  points: Slice[];
  emptyText: string;
}) {
  if (points.length < 2) return <p className={styles.empty}>{emptyText}</p>;

  const width = 100;
  const height = 34;
  const max = Math.max(...points.map((point) => point.value), 1);
  const step = width / (points.length - 1);

  const coords = points.map((point, index) => ({
    x: index * step,
    y: height - (point.value / max) * (height - 4) - 2,
  }));
  const line = coords
    .map((point, index) => `${index === 0 ? "M" : "L"}${point.x} ${point.y}`)
    .join(" ");
  const last = coords[coords.length - 1];
  const latest = points[points.length - 1];

  return (
    <div>
      <div className={styles.sparkBox}>
        <svg
          className={styles.spark}
          viewBox={`0 0 ${width} ${height}`}
          preserveAspectRatio="none"
          role="img"
          aria-label={`${latest.value} in the week of ${latest.label}, over ${points.length} weeks`}
        >
          <path
            className={styles.sparkArea}
            d={`${line} L${width} ${height} L0 ${height} Z`}
          />
          <path
            className={styles.sparkLine}
            d={line}
            vectorEffect="non-scaling-stroke"
          />
        </svg>
        {/* The end marker is an HTML element, not a <circle>: the plot is
            stretched to the card's width with preserveAspectRatio="none",
            which would flatten a circle into an ellipse. */}
        <span
          className={styles.sparkDot}
          style={{
            left: `${(last.x / width) * 100}%`,
            top: `${(last.y / height) * 100}%`,
          }}
        />
      </div>
      <div className={styles.sparkFoot}>
        <span>{points[0].label}</span>
        <span>
          <strong>{latest.value}</strong> in the week of {latest.label}
        </span>
      </div>
    </div>
  );
}
