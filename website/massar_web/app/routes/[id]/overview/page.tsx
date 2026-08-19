import { notFound } from "next/navigation";

import { fetchRoute, requireSession } from "@/lib/api";

import RouteOverview from "./RouteOverview";

/**
 * The page the traveller lives on while walking the route.
 *
 * The phone app's version of this screen is also where quests are drawn and
 * captures are taken; neither is here. What is left — where am I, what is next,
 * how much of this is done — is exactly the part a browser can answer, and it
 * is the part somebody following the route on a laptop or a second screen
 * actually wants.
 */
export default async function RouteOverviewPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const session = await requireSession();
  const route = await fetchRoute(session.token, id);

  if (!route || route.stops.length === 0) notFound();

  return <RouteOverview route={route} />;
}
