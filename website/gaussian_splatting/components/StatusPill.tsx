import type { JobStatus } from "@/lib/jobs";

import styles from "./StatusPill.module.css";

export function StatusPill({ status }: { status: JobStatus }) {
  return (
    <span className={`${styles.pill} ${styles[status]}`}>
      <span className={styles.dot} />
      {status}
    </span>
  );
}
