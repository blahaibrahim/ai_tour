"use client";

import { LogOut } from "lucide-react";
import { useState } from "react";

import { forgetAllRoutes } from "@/utils/progressStore";

import styles from "./settings.module.css";

/**
 * The way out of a walk in progress — the app's "Leave current tour".
 *
 * It clears where you had got to, not what was planned: the routes stay in your
 * history and can be opened and started again. Said in the row rather than left
 * to be discovered, because "leave" is the kind of word people reasonably read
 * as "delete".
 */
export default function LeaveTourRow() {
  const [left, setLeft] = useState<number | null>(null);

  return (
    <button
      type="button"
      className={`${styles.row} ${styles.rowButton} ${styles.danger}`}
      onClick={() => setLeft(forgetAllRoutes())}
    >
      <LogOut size={20} aria-hidden className={styles.rowIcon} />
      <span className={styles.rowCopy}>
        <span className={styles.rowTitle}>Leave current tour</span>
        <span className={styles.rowSubtitle}>
          {left === null
            ? "Forgets your place on any route you are part-way through. The routes themselves stay in your history."
            : left === 0
              ? "Nothing to leave — no route is in progress in this browser."
              : `Done. ${left} ${left === 1 ? "route" : "routes"} reset to the first stop.`}
        </span>
      </span>
    </button>
  );
}
