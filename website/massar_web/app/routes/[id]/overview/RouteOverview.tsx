"use client";

import { Clock, Flag, ListOrdered, Settings, Trophy } from "lucide-react";
import Link from "next/link";
import { useCallback, useSyncExternalStore } from "react";

import AppBackdrop from "@/components/AppBackdrop";
import NetImage from "@/components/NetImage";
import RouteMap from "@/components/RouteMap";
import { formatMinutes } from "@/lib/format";
import type { GeneratedRoute } from "@/lib/types";
import { apiFetch } from "@/utils/apiFetch";
import {
  readCurrentStop,
  readCurrentStopOnServer,
  readProgressId,
  rememberCurrentStop,
  subscribeToCurrentStop,
} from "@/utils/progressStore";

import styles from "./overview.module.css";

/**
 * A dark header over light content cards.
 *
 * The backdrop runs from navy at the top to cream at the bottom, so white text
 * used throughout the page would be white-on-near-white by the time you have
 * scrolled past the hero. Everything below the hero sits on an explicit
 * surface and takes the normal ink colour, which makes contrast a property of
 * the layout rather than of scroll offset.
 */
export default function RouteOverview({ route }: { route: GeneratedRoute }) {
  // Where the traveller is on this route lives in `localStorage`, which is
  // state React does not own — so it is read as an external store rather than
  // mirrored into an effect. That also means a second tab moving the cursor
  // moves this one, and there is no render where the two disagree.
  const stored = useSyncExternalStore(
    subscribeToCurrentStop,
    useCallback(() => readCurrentStop(route.id), [route.id]),
    readCurrentStopOnServer,
  );
  const currentIdx = Math.min(stored, route.stops.length);

  const currentStop = currentIdx < route.stops.length ? route.stops[currentIdx] : null;
  const upcoming = route.stops.slice(currentIdx + 1);

  /**
   * Moves to the next stop, and logs the arrival at the one just finished.
   *
   * The checkpoint is fire-and-forget. It is a record for the profile, not a
   * precondition for walking on, and making the traveller wait on it — or
   * refusing to advance when it fails — would put a bookkeeping call in front
   * of the only control this page has.
   */
  function advance() {
    if (!currentStop) return;

    const progressId = readProgressId(route.id);
    if (progressId) {
      void apiFetch(`/api/progress/${progressId}/checkpoint`, {
        method: "POST",
        body: JSON.stringify({ poi_id: currentStop.poi_id }),
      }).catch(() => {});
    }

    // The write *is* the state change: `rememberCurrentStop` notifies the
    // store, and the subscription above re-renders this page from it.
    rememberCurrentStop(route.id, currentIdx + 1);
  }

  function restart() {
    rememberCurrentStop(route.id, 0);
  }

  return (
    <AppBackdrop variant="deep">
      <main className={styles.page}>
        <header className={styles.header}>
          <div className={styles.headerCopy}>
            <p className="sectionLabel sectionLabel-onDark">YOUR ROUTE</p>
            <h1 className={styles.headerTitle}>Overview</h1>
          </div>
          <Link href={`/routes/${route.id}`} className={styles.iconButton} aria-label="Itinerary">
            <ListOrdered size={20} aria-hidden />
          </Link>
          <Link href="/settings" className={styles.iconButton} aria-label="Settings">
            <Settings size={20} aria-hidden />
          </Link>
        </header>

        <section className={styles.status}>
          <p className="sectionLabel sectionLabel-onDark">
            {currentStop
              ? `STOP ${currentIdx + 1} OF ${route.stops.length}`
              : "ROUTE COMPLETE"}
          </p>
          <p className={styles.statusName}>{currentStop?.name ?? "All done!"}</p>
        </section>

        {/* Per-stop progress. Segmented rather than dots, so it scales past the
            handful of stops a dot row stays readable at. */}
        <div
          className={styles.track}
          role="img"
          aria-label={
            currentStop
              ? `Stop ${currentIdx + 1} of ${route.stops.length}`
              : "Every stop visited"
          }
        >
          {route.stops.map((stop, index) => (
            <span
              key={stop.poi_id}
              className={styles.tick}
              data-state={
                index < currentIdx ? "done" : index === currentIdx ? "current" : "upcoming"
              }
            />
          ))}
        </div>

        {currentStop ? (
          <>
            <article className={styles.hero}>
              <NetImage url={currentStop.photo_url} alt="" className={styles.heroPhoto} />
              <div className={styles.heroScrim} aria-hidden />
              <div className={styles.heroCopy}>
                <div>
                  <h2 className={styles.heroName}>{currentStop.name}</h2>
                  <p className={styles.heroMeta}>
                    <Clock size={13} aria-hidden />
                    {formatMinutes(currentStop.dwell_minutes)} here
                    {currentStop.category_key ? ` · ${currentStop.category_key}` : ""}
                  </p>
                </div>
                {currentIdx < route.stops.length - 1 ? (
                  <button type="button" className={styles.endVisit} onClick={advance}>
                    End visit
                  </button>
                ) : (
                  <button type="button" className={styles.endVisit} onClick={advance}>
                    <Flag size={15} aria-hidden />
                    Finish route
                  </button>
                )}
              </div>
            </article>

            {currentStop.description ? (
              <section className={styles.card}>
                <h3 className="sectionLabel">ABOUT THIS STOP</h3>
                <p className={styles.about}>{currentStop.description}</p>
              </section>
            ) : null}

            <section className={styles.card}>
              <h3 className="sectionLabel">WHERE YOU ARE ON THE ROUTE</h3>
              <div className={styles.mapFrame}>
                {/* The active pin is filled and the ones behind it are ticked,
                    so the map answers "how far along am I" without a legend. */}
                <RouteMap route={route} activeStopIndex={currentIdx} />
              </div>
            </section>
          </>
        ) : (
          <section className={styles.card}>
            <div className={styles.done}>
              <span className={styles.doneMark} aria-hidden>
                <Trophy size={32} />
              </span>
              <h2 className={styles.doneTitle}>Route complete!</h2>
              <p className={styles.doneCopy}>
                You visited every stop on this route.
              </p>
              <div className={styles.doneActions}>
                <button type="button" className="btn btn-outline" onClick={restart}>
                  Walk it again
                </button>
                <Link href="/generate" className="btn btn-primary">
                  Plan another
                </Link>
              </div>
            </div>
          </section>
        )}

        {upcoming.length > 0 ? (
          <section className={styles.upcoming}>
            {/* White, not the grey secondary: this label sits on the backdrop
                rather than on a card, and matches the other labels above it. */}
            <h3 className="sectionLabel sectionLabel-onDark">UPCOMING</h3>
            <ul className={styles.upcomingRow}>
              {upcoming.map((stop, index) => (
                <li key={stop.poi_id} className={styles.upcomingCard}>
                  <NetImage url={stop.photo_url} alt="" className={styles.upcomingPhoto} />
                  <span className={styles.upcomingScrim} aria-hidden />
                  {/* The stop's position on the route. Without it a strip of
                      photos says nothing about order, which is the one thing an
                      itinerary is. */}
                  <span className={styles.upcomingIndex}>{currentIdx + index + 2}</span>
                  <span className={styles.upcomingName}>{stop.name}</span>
                </li>
              ))}
            </ul>
          </section>
        ) : null}

        {/* Said out loud because it is the one surprising thing about this
            page: the cursor is local, so a walk resumed on another device
            starts at the top even though the arrivals behind it were logged. */}
        <p className={styles.footnote}>
          Your place on this route is kept in this browser. Arrivals are logged to your
          account as you go.
        </p>
      </main>
    </AppBackdrop>
  );
}
