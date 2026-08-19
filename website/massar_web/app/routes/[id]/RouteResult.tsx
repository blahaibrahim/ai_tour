"use client";

import {
  Car,
  Check,
  ChevronLeft,
  Clock,
  Footprints,
  MapPin,
  Pencil,
  Sunset,
  Trash2,
} from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";

import AppBackdrop from "@/components/AppBackdrop";
import NetImage from "@/components/NetImage";
import Notice from "@/components/Notice";
import RouteMap from "@/components/RouteMap";
import RouteMapLegend from "@/components/RouteMapLegend";
import {
  distanceLabel,
  formatMinutes,
  legInto,
  needsMoreThanOneDay,
  routeTitle,
} from "@/lib/format";
import type { GeneratedRoute, RouteProgress, RouteStop } from "@/lib/types";
import { apiFetch } from "@/utils/apiFetch";
import { rememberProgressId } from "@/utils/progressStore";

import styles from "./route.module.css";

export default function RouteResult({ route: initialRoute }: { route: GeneratedRoute }) {
  const router = useRouter();

  const [route, setRoute] = useState(initialRoute);
  const [modifyMode, setModifyMode] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /**
   * Drops one stop and re-generates around the gap.
   *
   * Modelled as "generate again, excluding this" rather than as an edit,
   * because the order is the optimizer's output over a real travel-time matrix
   * — deleting an entry from the list in place would leave every leg duration
   * and the route total describing a route that no longer exists.
   */
  async function removeStop(stop: RouteStop) {
    if (!canRemoveStop(route, stop)) {
      setError("Removing that would leave less than the time you asked for.");
      return;
    }

    setBusy(true);
    setError(null);
    try {
      const refined = await apiFetch<GeneratedRoute>(`/api/routes/${route.id}/refine`, {
        method: "POST",
        body: JSON.stringify({
          drop_poi_ids: [stop.poi_id],
          // `/refine` re-runs generation, so it needs the original criteria
          // back — it is not a patch against the stored route.
          city_id: route.city_id,
          theme: route.theme,
          time_budget_minutes: route.time_budget_minutes,
          transport_mode: route.transport_mode,
          locale: "en",
        }),
      });

      setRoute(refined);
      // A refine can come back under a new id. Keeping the URL pointing at the
      // route that was replaced would make a reload undo the removal.
      if (refined.id !== route.id) router.replace(`/routes/${refined.id}`);
    } catch {
      setError("Couldn't remove that stop — try again.");
    } finally {
      setBusy(false);
    }
  }

  /** Accepts the route and opens a progress record for the walk. */
  async function startRoute() {
    setBusy(true);
    setError(null);
    try {
      const progress = await apiFetch<RouteProgress>(`/api/routes/${route.id}/progress`, {
        method: "POST",
      });
      rememberProgressId(route.id, progress.id);
    } catch {
      // The walk still works without a server-side progress record; the
      // checkpoints simply are not logged. Blocking the traveller at the start
      // line over a bookkeeping call would be the wrong trade.
    }
    router.push(`/routes/${route.id}/overview`);
  }

  const title = routeTitle({ city_name: null, theme: route.theme });

  return (
    <AppBackdrop>
      <div className={styles.page}>
        <header className={styles.mapHeader}>
          <div className={styles.mapFrame}>
            {/* No pin labels here: the itinerary immediately below names every
                stop in order, and a permanent plate on each pin would cover
                the streets the map is being shown for. The full-screen map in
                the app labels them because it has nothing underneath it. */}
            <RouteMap route={route} />
          </div>
          <Link href="/home" className={styles.floatingBack} aria-label="Back to your routes">
            <ChevronLeft size={19} aria-hidden />
          </Link>
        </header>

        <main className={styles.body}>
          <h1 className={styles.title}>{title}</h1>

          <section className={styles.summary}>
            <div className={styles.stats}>
              <Stat
                icon={<Clock size={16} />}
                value={formatMinutes(route.estimated_total_duration_minutes)}
                label="total"
                emphasised
              />
              <Stat
                icon={<MapPin size={16} />}
                value={String(route.stops.length)}
                label={route.stops.length === 1 ? "stop" : "stops"}
              />
            </div>
            <hr className={styles.rule} />
            {/* Doubles as the map's key — same colours, same dash language. */}
            <RouteMapLegend route={route} />
          </section>

          {/* From the module's isochrone check, not a stops-per-day heuristic:
              it says the remaining stops are not reachable in what is left of
              the budget, which is a fact about geography rather than
              arithmetic. */}
          {needsMoreThanOneDay(route) ? (
            <Notice
              tone="warning"
              icon={<Sunset size={18} />}
              title={`Longer than your ${formatMinutes(route.time_budget_minutes)}`}
            >
              {`This route needs about ${formatMinutes(
                route.estimated_total_duration_minutes,
              )}. Plan on ${route.day_count_flag} days, or remove a few stops below.`}
            </Notice>
          ) : null}

          {error ? (
            <Notice tone="error" title="Something went wrong">
              {error}
            </Notice>
          ) : null}

          <div className={styles.itineraryHead}>
            <h2 className="sectionLabel">ITINERARY</h2>
            {/* "Modify manually" promised reordering, which this page does not
                offer: the order is the optimizer's and cannot be hand-dragged
                without invalidating every duration on it. Removing stops is
                what the mode actually does, so that is what it says. */}
            <button
              type="button"
              className={styles.modifyToggle}
              data-on={modifyMode}
              onClick={() => setModifyMode((on) => !on)}
            >
              {modifyMode ? <Check size={16} aria-hidden /> : <Pencil size={16} aria-hidden />}
              {modifyMode ? "Done" : "Remove stops"}
            </button>
          </div>

          <ol className={styles.itinerary}>
            {route.stops.map((stop, index) => (
              <li key={stop.poi_id} className={styles.stopItem} style={{ "--i": index } as React.CSSProperties}>
                {legInto(route, index) ? <Leg segment={legInto(route, index)!} /> : null}

                <div className={styles.stopRow}>
                  <span className={styles.stopIndex}>{index + 1}</span>
                  <NetImage url={stop.photo_url} alt="" className={styles.stopPhoto} />
                  <div className={styles.stopCopy}>
                    <p className={styles.stopName}>{stop.name}</p>
                    <p className={styles.stopMeta}>
                      <Clock size={11} aria-hidden />
                      {formatMinutes(stop.dwell_minutes)} here
                      {stop.category_key ? ` · ${stop.category_key}` : ""}
                    </p>
                    {stop.description ? (
                      <p className={styles.stopDescription}>{stop.description}</p>
                    ) : null}
                  </div>

                  {modifyMode && canRemoveStop(route, stop) ? (
                    <button
                      type="button"
                      className={styles.removeButton}
                      disabled={busy}
                      onClick={() => removeStop(stop)}
                      aria-label={`Remove ${stop.name}`}
                    >
                      <Trash2 size={18} aria-hidden />
                    </button>
                  ) : null}
                </div>
              </li>
            ))}
          </ol>
        </main>

        {/* The commit action, pinned. As a trailing element it sat below the
            fold on any route longer than about four stops — the primary action
            reachable only by scrolling to the end of a list whose whole purpose
            is to be skimmed. */}
        <div className={styles.acceptBar}>
          <div className={styles.acceptInner}>
            <div className={styles.acceptCopy}>
              <p className={styles.acceptStops}>
                {route.stops.length} {route.stops.length === 1 ? "stop" : "stops"}
              </p>
              <p className={styles.acceptTime}>
                {formatMinutes(route.estimated_total_duration_minutes)}
              </p>
            </div>
            <button type="button" className="btn btn-primary" disabled={busy} onClick={startRoute}>
              {busy ? "Working…" : "Start this route"}
            </button>
          </div>
        </div>
      </div>
    </AppBackdrop>
  );
}

/** One travel leg between two stops, with its mode tag. The tag is the
 *  server's; inferring it from a change of cluster breaks the moment a cluster
 *  holds one stop. */
function Leg({ segment }: { segment: GeneratedRoute["segments"][number] }) {
  const isDrive = segment.mode === "drive";

  return (
    <p className={styles.leg} data-mode={segment.mode}>
      <span className={styles.legLine} aria-hidden />
      {isDrive ? <Car size={15} aria-hidden /> : <Footprints size={15} aria-hidden />}
      <span className={styles.legMode}>{isDrive ? "Drive" : "Walk"}</span>
      <span className={styles.legDetail}>
        {formatMinutes(segment.duration_minutes)} · {distanceLabel(segment.distance_meters)}
      </span>
    </p>
  );
}

function Stat({
  icon,
  value,
  label,
  emphasised = false,
}: {
  icon: React.ReactNode;
  value: string;
  label: string;
  emphasised?: boolean;
}) {
  return (
    // The icon is decorative — value and label already say everything — so the
    // whole stat is announced as one string rather than three nodes.
    <div className={styles.stat} data-emphasised={emphasised} aria-label={`${value} ${label}`}>
      <span className={styles.statIcon} aria-hidden>
        {icon}
      </span>
      <span className={styles.statValue}>{value}</span>
      <span className={styles.statLabel}>{label}</span>
    </div>
  );
}

/**
 * Whether the route can lose this stop and still fill the time asked for.
 *
 * A traveller may trim their day, but not below the day they requested. The
 * bar is not the raw budget: a city's catalogue frequently cannot fill a whole
 * one — Constantine's "culture" theme has a single POI in it — so requiring the
 * full budget would leave people stuck behind a control that can never unlock.
 * The route the module produced is the most it could offer, so clearing *that*
 * is the honest test.
 *
 * In practice this means removal opens up on exactly the routes that invite it:
 * the ones that came back longer than the budget, where the day-count notice
 * has just suggested dropping a few stops.
 */
function canRemoveStop(route: GeneratedRoute, stop: RouteStop): boolean {
  if (route.stops.length <= 1) return false;

  // Derived rather than assumed: the route's own estimate minus the dwell it
  // accounts for is its travel, and dividing by the stop count gives what one
  // stop costs to reach. Using the server's numbers means the gate agrees with
  // the route the server actually built.
  const dwell = route.stops.reduce((sum, s) => sum + s.dwell_minutes, 0);
  const travel = Math.max(0, route.estimated_total_duration_minutes - dwell);
  const travelPerStop = travel / route.stops.length;

  const required = Math.min(route.estimated_total_duration_minutes, route.time_budget_minutes);
  const after = route.estimated_total_duration_minutes - stop.dwell_minutes - travelPerStop;
  return after >= required;
}
