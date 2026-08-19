import type { ReactNode } from "react";

import styles from "./AppBackdrop.module.css";

export type AppBackdropVariant = "sky" | "deep" | "warm" | "duotone";

/**
 * The page background: a faint gradient, a subtle grain, and a few dotted
 * travel trails.
 *
 * A direct port of `lib/widgets/app_backdrop.dart`, including its decision not
 * to animate. A background that moves competes with the content for attention;
 * the trails give the page the "journey" reading the drifting gradient used to,
 * without anything repainting behind a scrolling list or a live map.
 *
 * The trails are dashed curves ending in a dot — the same visual language the
 * route map uses for a walking leg between two stops, at the same 5/6 dash
 * rhythm, so the decoration and the data speak with one voice.
 */
export default function AppBackdrop({
  children,
  variant = "sky",
  className,
}: {
  children: ReactNode;
  variant?: AppBackdropVariant;
  className?: string;
}) {
  return (
    <div
      className={[
        styles.backdrop,
        `backdrop-${variant}`,
        variant === "deep" ? "onDark" : "",
        className ?? "",
      ]
        .filter(Boolean)
        .join(" ")}
    >
      <Trails variant={variant} />
      <div className={styles.grain} aria-hidden />
      <div className={styles.content}>{children}</div>
    </div>
  );
}

/**
 * Trails in normalised coordinates, matching `_DottedTrailsPainter` curve for
 * curve.
 *
 * Fixed rather than random, so the background is identical on every render — a
 * pattern that reshuffles between navigations looks like a glitch. They sit
 * toward the edges, where page content is thinnest, and several run off-canvas
 * so the page feels like a window onto something larger rather than a box with
 * four arcs in it.
 */
const TRAILS = [
  { d: "M-5,30 C18,14 10,2 30,-2", end: [30, -2] },
  { d: "M62,10 C80,2 102,16 88,26", end: [88, 26] },
  { d: "M-2,72 C30,62 42,92 72,80", end: [72, 80] },
  { d: "M78,94 C90,86 94,102 105,92", end: [105, 92] },
] as const;

function Trails({ variant }: { variant: AppBackdropVariant }) {
  // Navy on the duotone ramp rather than either brand colour: the trails cross
  // the whole gradient, and a blue one vanishes into the bottom while a warm
  // one vanishes into the top.
  const colour = {
    sky: "rgba(47, 84, 154, 0.35)",
    deep: "rgba(255, 255, 255, 0.4)",
    warm: "rgba(120, 59, 30, 0.35)",
    duotone: "rgba(20, 37, 74, 0.18)",
  }[variant];

  return (
    <div className={styles.trails} aria-hidden>
      <svg
        className={styles.trailsSvg}
        viewBox="0 0 100 100"
        preserveAspectRatio="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        {/* `non-scaling-stroke` keeps both the 1.6px width and the dash rhythm
            in screen units, which is what stops the pattern from stretching
            with the viewport under `preserveAspectRatio="none"`. */}
        <g
          fill="none"
          stroke={colour}
          strokeWidth="1.6"
          strokeDasharray="5 6"
          strokeLinecap="round"
          vectorEffect="non-scaling-stroke"
        >
          {TRAILS.map((trail) => (
            <path key={trail.d} d={trail.d} vectorEffect="non-scaling-stroke" />
          ))}
        </g>
      </svg>

      {/* The destination dots are positioned rather than drawn into the SVG:
          under a non-uniform scale a <circle> becomes an ellipse, and a
          squashed full stop is the one part of the pattern the eye catches. */}
      {TRAILS.map((trail) => (
        <span
          key={`${trail.end[0]}-${trail.end[1]}`}
          className={styles.trailDot}
          style={{
            left: `${trail.end[0]}%`,
            top: `${trail.end[1]}%`,
            background: colour,
          }}
        />
      ))}
    </div>
  );
}
