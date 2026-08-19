import { Compass } from "lucide-react";
import Link from "next/link";

import AppBackdrop from "@/components/AppBackdrop";
import { fetchRoute, requireSession } from "@/lib/api";

import RouteResult from "./RouteResult";
import styles from "./route.module.css";

/**
 * The generated route, before the traveller commits to walking it.
 *
 * The map earns the top of the page — it is the answer to "what did you plan
 * for me" — and the itinerary underneath is what the answer says in words.
 */
export default async function RouteDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const session = await requireSession();
  const route = await fetchRoute(session.token, id);

  if (!route) return <RouteNotFound />;
  if (route.stops.length === 0) return <NoStopsLeft />;

  return <RouteResult route={route} />;
}

/** Not found and not yours are the same answer from here, and deliberately so:
 *  telling somebody a route id exists but is not theirs is more than they
 *  asked and more than they should get. */
function RouteNotFound() {
  return (
    <EmptyState
      title="No route here"
      body="That route either doesn't exist or belongs to another account."
    />
  );
}

/** Generation succeeded but nothing survived — every stop dropped in review, or
 *  a theme with no published stops in this city. */
function NoStopsLeft() {
  return (
    <EmptyState
      title="No stops left"
      body="Try another theme, a longer time budget, or a different city."
    />
  );
}

function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <AppBackdrop>
      <main className={styles.emptyPage}>
        <span className={styles.emptyMark} aria-hidden>
          <Compass size={34} />
        </span>
        <h1 className={styles.emptyTitle}>{title}</h1>
        <p className={styles.emptyBody}>{body}</p>
        <Link href="/generate" className="btn btn-primary">
          Plan a route
        </Link>
      </main>
    </AppBackdrop>
  );
}
