import { ArrowRight, ChevronRight, Compass, Route, Settings } from "lucide-react";
import Link from "next/link";

import AppBackdrop from "@/components/AppBackdrop";
import GlassSurface from "@/components/GlassSurface";
import PointsPill from "@/components/PointsPill";
import { fetchMyRoutes, requireSession } from "@/lib/api";
import { relativeDay, routeSubtitle, routeTitle } from "@/lib/format";
import type { RouteSummary } from "@/lib/types";
import { createClient } from "@/utils/supabase/server";

import styles from "./home.module.css";

/**
 * Where the site opens, and where it returns between trips.
 *
 * It answers the two things a traveller who is not currently walking wants:
 * plan another route, or look at the ones they have already made. The phone app
 * adds a shop to that list; this one does not, because the points it would
 * spend are earned by finishing tasks at a stop, and that half of the app —
 * quests, the camera, the AR hunt — is not something a browser can do.
 */
export default async function HomePage() {
  const session = await requireSession();
  const [routes, points] = await Promise.all([
    fetchMyRoutes(session.token),
    fetchLifetimePoints(),
  ]);

  return (
    <AppBackdrop variant="deep">
      <main className={styles.page}>
        <header className={styles.header}>
          <div className={styles.brand}>
            <p className="sectionLabel sectionLabel-onDark">MASSAR</p>
            <h1 className={styles.greeting}>Where to next?</h1>
          </div>
          <PointsPill
            value={points}
            semanticLabel={
              points === null ? "Points syncing" : `${points} points earned in the app`
            }
          />
          <Link href="/settings" className={styles.iconButton} aria-label="Settings">
            <Settings size={20} aria-hidden />
          </Link>
        </header>

        <Link href="/generate" className={styles.startCard}>
          <span className={styles.startIcon} aria-hidden>
            <Compass size={22} />
          </span>
          <span className={styles.startCopy}>
            <span className={styles.startTitle}>Plan a new route</span>
            <span className={styles.startSubtitle}>
              Pick a city, say what you are after, and how long you have
            </span>
          </span>
          <ArrowRight size={20} aria-hidden className={styles.startArrow} />
        </Link>

        <section className={styles.history}>
          <h2 className="sectionLabel sectionLabel-onDark">YOUR ROUTES</h2>
          {routes.length === 0 ? <NoRoutesYet /> : routes.map((route) => (
            <RouteCard key={route.id} route={route} />
          ))}
        </section>
      </main>
    </AppBackdrop>
  );
}

function RouteCard({ route }: { route: RouteSummary }) {
  const when = relativeDay(route.generated_at);

  return (
    <GlassSurface className={styles.routeCard}>
      <Link href={`/routes/${route.id}`} className={styles.routeLink}>
        <span className={styles.routeIcon} aria-hidden>
          <Route size={20} />
        </span>
        <span className={styles.routeCopy}>
          <span className={styles.routeTitleRow}>
            <span className={styles.routeTitle}>{routeTitle(route)}</span>
            {when ? <span className={styles.routeWhen}>{when}</span> : null}
          </span>
          <span className={styles.routeSubtitle}>{routeSubtitle(route)}</span>
        </span>
        <ChevronRight size={20} aria-hidden className={styles.routeChevron} />
      </Link>
    </GlassSurface>
  );
}

function NoRoutesYet() {
  return (
    <GlassSurface className={styles.emptyCard}>
      <Route size={20} aria-hidden className={styles.emptyIcon} />
      <p className={styles.emptyCopy}>
        Routes you generate will collect here, ready to pick up again.
      </p>
    </GlassSurface>
  );
}

/**
 * The traveller's lifetime score, read straight from `profiles`.
 *
 * Not from the Node API: points are a Supabase concern with their own RLS, and
 * the route service has no endpoint for them. Null on any failure, which the
 * pill renders as a dash — "not synced yet" is not the same fact as zero, and a
 * 0 here would tell somebody with 400 points that they have none.
 */
async function fetchLifetimePoints(): Promise<number | null> {
  const supabase = await createClient();
  const { data } = await supabase.from("profiles").select("total_points").maybeSingle();
  const total = (data as { total_points?: number } | null)?.total_points;
  return typeof total === "number" ? total : null;
}
