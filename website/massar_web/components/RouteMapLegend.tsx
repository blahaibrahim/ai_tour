import { driveMinutes, formatMinutes, walkMinutes } from "@/lib/format";
import type { GeneratedRoute } from "@/lib/types";

import styles from "./RouteMapLegend.module.css";

/**
 * The map's colour key.
 *
 * Without it the two stroke colours are decoration. The drive/walk split is
 * the main thing the hybrid transport model produces, so it is worth a line of
 * vertical space to make the map self-explanatory — and the swatches are drawn
 * in the same solid/dashed language the map uses, so the key *is* the thing it
 * describes rather than a pair of coloured squares.
 */
export default function RouteMapLegend({ route }: { route: GeneratedRoute }) {
  const hasDrive = route.segments.some((s) => s.mode === "drive");

  return (
    <ul className={styles.legend}>
      {hasDrive ? (
        <li className={styles.entry}>
          <span className={`${styles.swatch} ${styles.drive}`} aria-hidden />
          Drive · {formatMinutes(driveMinutes(route))}
        </li>
      ) : null}
      <li className={styles.entry}>
        <span className={`${styles.swatch} ${styles.walk}`} aria-hidden />
        Walk · {formatMinutes(walkMinutes(route))}
      </li>
    </ul>
  );
}
