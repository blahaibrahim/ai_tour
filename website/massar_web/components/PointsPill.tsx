import { Star } from "lucide-react";

import styles from "./PointsPill.module.css";

/**
 * The score readout for the dark headers.
 *
 * `null` renders as a dash, and that is the point: it means "not synced yet",
 * and a 0 in its place would tell a traveller with 400 points that they have
 * none.
 *
 * The number is earned in the phone app — walking routes and finishing the
 * tasks at each stop. The web planner has no way to add to it, so this is a
 * readout and never a control; there is no shop button beside it here for the
 * same reason.
 */
export default function PointsPill({
  value,
  semanticLabel,
}: {
  value: number | null;
  semanticLabel: string;
}) {
  return (
    <span className={styles.pill} title={semanticLabel} aria-label={semanticLabel}>
      <Star size={15} className={styles.icon} aria-hidden />
      <span className={styles.value}>{value ?? "—"}</span>
    </span>
  );
}
