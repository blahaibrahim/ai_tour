"use client";

import { useEffect, useRef, useState } from "react";

import type { Job } from "@/lib/jobs";
import { formatDuration, formatUsd } from "@/lib/pipeline";

import { StatusPill } from "./StatusPill";
import styles from "./JobCard.module.css";

function elapsedOf(job: Job): string {
  if (!job.startedAt) return "—";
  const end = job.finishedAt ? Date.parse(job.finishedAt) : Date.now();
  return formatDuration((end - Date.parse(job.startedAt)) / 1000);
}

export function JobCard({ job, defaultOpen }: { job: Job; defaultOpen: boolean }) {
  const [open, setOpen] = useState(defaultOpen);
  const [copied, setCopied] = useState<string | null>(null);
  const logRef = useRef<HTMLPreElement>(null);
  const pinned = useRef(true);

  const active = job.status === "running" || job.status === "queued";

  // Follow the tail while the reader is at the bottom, and stop the moment
  // they scroll up to read something — otherwise a chatty stage yanks the view
  // away mid-line.
  useEffect(() => {
    const element = logRef.current;
    if (!element || !open || !pinned.current) return;
    element.scrollTop = element.scrollHeight;
  }, [job.log.length, open]);

  // A running job's elapsed time has to move on its own; nothing else changes.
  const [, tick] = useState(0);
  useEffect(() => {
    if (!active) return;
    const timer = setInterval(() => tick((n) => n + 1), 1_000);
    return () => clearInterval(timer);
  }, [active]);

  async function cancel(event: React.MouseEvent) {
    event.stopPropagation();
    await fetch(`/api/jobs/${job.id}`, { method: "DELETE" });
  }

  async function copy(command: string) {
    await navigator.clipboard.writeText(command);
    setCopied(command);
    setTimeout(() => setCopied(null), 1_500);
  }

  return (
    <div className={styles.card}>
      <button
        type="button"
        className={styles.head}
        onClick={() => setOpen((value) => !value)}
        aria-expanded={open}
      >
        <span className={`${styles.chevron} ${open ? styles.open : ""}`}>▶</span>
        <span className={styles.identity}>
          <span className={styles.scene}>{job.scene}</span>
          <span className={styles.meta}>
            {job.stage} · {job.quality} · {job.sceneType} · {elapsedOf(job)} · est.
            ~{formatUsd(job.estimateUsd)}
          </span>
        </span>
        <StatusPill status={job.status} />
      </button>

      {open ? (
        <div className={styles.body}>
          {job.log.length === 0 ? (
            <p className={styles.empty}>Waiting for output…</p>
          ) : (
            <pre
              ref={logRef}
              className={styles.log}
              onScroll={(event) => {
                const el = event.currentTarget;
                pinned.current =
                  el.scrollHeight - el.scrollTop - el.clientHeight < 32;
              }}
            >
              {job.log.map((line, index) => (
                <div
                  key={index}
                  className={
                    line.stream === "err"
                      ? styles.err
                      : line.stream === "sys"
                        ? styles.sys
                        : undefined
                  }
                >
                  {line.text || " "}
                </div>
              ))}
            </pre>
          )}

          {job.artifacts.length > 0 ? (
            <div className={styles.artifacts}>
              <span className={styles.artifactLabel}>Fetch the result</span>
              {job.artifacts.map((command) => (
                <div className={styles.artifact} key={command}>
                  <code>{command}</code>
                  <button
                    type="button"
                    className={styles.copy}
                    onClick={() => copy(command)}
                  >
                    {copied === command ? "copied" : "copy"}
                  </button>
                </div>
              ))}
            </div>
          ) : null}

          {active ? (
            <div className={styles.actions}>
              <button type="button" className={styles.cancel} onClick={cancel}>
                Cancel run
              </button>
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
