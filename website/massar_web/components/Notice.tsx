import type { ReactNode } from "react";

import styles from "./Notice.module.css";

export type NoticeTone = "warning" | "error" | "success";

/**
 * A titled inline message.
 *
 * One component for the day-count flag and for a generation error, so the two
 * read as the same kind of object at different severities. The tones are not
 * interchangeable: a route that needs a second day is a good route with a
 * scheduling consequence, and painting it in the error colour told travellers
 * something had gone wrong.
 */
export default function Notice({
  tone,
  icon,
  title,
  children,
}: {
  tone: NoticeTone;
  icon?: ReactNode;
  title: string;
  children?: ReactNode;
}) {
  return (
    <div className={`${styles.notice} ${styles[tone]}`} role={tone === "error" ? "alert" : undefined}>
      {icon ? (
        <span className={styles.icon} aria-hidden>
          {icon}
        </span>
      ) : null}
      <div>
        <p className={styles.title}>{title}</p>
        {children ? <p className={styles.body}>{children}</p> : null}
      </div>
    </div>
  );
}
