import styles from "./CompassSpinner.module.css";

/**
 * The app icon's brass compass, redrawn as the loading indicator.
 *
 * A port of `lib/widgets/compass_spinner.dart`: the housing — bail, brass
 * case, blue face — stays put while the needle sweeps, accelerating away and
 * easing to a stop once per revolution, the way a real needle hunts for north.
 * The easing is flat at both ends, so the loop is seamless while still reading
 * as a swing-and-settle rather than a spin.
 *
 * Geometry is the painter's, evaluated at s = 100 and expressed in a viewBox,
 * so the numbers below are the Flutter ones scaled once rather than re-tuned.
 */
export default function CompassSpinner({ size = 64 }: { size?: number }) {
  return (
    <svg
      className={styles.spinner}
      width={size}
      height={size}
      viewBox="0 0 100 100"
      role="progressbar"
      aria-label="Working"
      xmlns="http://www.w3.org/2000/svg"
    >
      {/* Bail — the little hanging loop poking out of the top of the case.
          Stroked, not filled, so whatever is behind shows through the loop. */}
      <circle cx="50" cy="12.2" r="5.8" fill="none" stroke="var(--amber)" strokeWidth="4.2" />
      <circle cx="50" cy="12.2" r="7.9" fill="none" stroke="var(--cocoa)" strokeWidth="1.6" />
      <circle cx="50" cy="12.2" r="3.7" fill="none" stroke="var(--cocoa)" strokeWidth="1.6" />

      {/* Brass case, then the blue face inset so the brass reads as a rim. */}
      <circle cx="50" cy="55" r="42" fill="var(--amber)" stroke="var(--cocoa)" strokeWidth="3.2" />
      <circle
        cx="50"
        cy="55"
        r="31.9"
        fill="var(--compass-blue)"
        stroke="rgba(120, 59, 30, 0.55)"
        strokeWidth="2.2"
      />

      {/* The needle: a slim lens split down its long axis, cream on the leading
          side and brass on the trailing side, exactly as in the icon. The
          control points sit at twice the waist so each half bulges widest at
          the pivot. */}
      <g className={styles.needle}>
        <path
          d="M50,26.9 Q37.2,55 50,83.1 Z"
          fill="var(--cream)"
          stroke="rgba(120, 59, 30, 0.75)"
          strokeWidth="1.6"
        />
        <path
          d="M50,26.9 Q62.8,55 50,83.1 Z"
          fill="var(--amber)"
          stroke="rgba(120, 59, 30, 0.75)"
          strokeWidth="1.6"
        />
      </g>

      <circle cx="50" cy="55" r="2.6" fill="var(--cocoa)" />
    </svg>
  );
}
