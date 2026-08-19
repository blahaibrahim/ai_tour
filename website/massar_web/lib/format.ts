/**
 * The formatting rules the route surfaces share.
 *
 * Ported from `lib/models/route.dart` rather than re-invented: the phone and
 * the browser show the same route, and "4h 20m" on one and "260 min" on the
 * other would read as two different numbers.
 */

import type { GeneratedRoute, RouteSegment, RouteSummary, TransportMode } from "./types";

/** `45 min`, `4h`, `4h 20m`. */
export function formatMinutes(minutes: number): string {
  const total = Math.max(0, Math.round(minutes));
  if (total < 60) return `${total} min`;
  const hours = Math.floor(total / 60);
  const rest = total % 60;
  return rest === 0 ? `${hours}h` : `${hours}h ${rest}m`;
}

/** `0.9 km` past a kilometre, `640 m` below it. */
export function distanceLabel(metres: number): string {
  return metres >= 1000 ? `${(metres / 1000).toFixed(1)} km` : `${Math.round(metres)} m`;
}

export function transportLabel(mode: TransportMode): string {
  switch (mode) {
    case "walking":
      return "Walking";
    case "driving":
      return "Driving";
    default:
      return "Drive + walk";
  }
}

/**
 * The leg that leads *into* the stop at [index], or null for the first.
 *
 * Indexed by position, not matched on `to_poi_id`. Matching on the id looks
 * right and silently hides every drive: an inter-cluster leg runs anchor to
 * anchor, so both its POI ids are null by design. The server emits legs in
 * exactly the order the stops are visited, which is `stops.length - 1` legs,
 * each sitting between consecutive stops.
 */
export function legInto(route: GeneratedRoute, index: number): RouteSegment | null {
  if (index <= 0) return null;
  const leg = route.segments[index - 1];
  return leg ?? null;
}

export function driveMinutes(route: GeneratedRoute): number {
  return route.segments
    .filter((s) => s.mode === "drive")
    .reduce((sum, s) => sum + s.duration_minutes, 0);
}

export function walkMinutes(route: GeneratedRoute): number {
  return route.segments
    .filter((s) => s.mode === "walk")
    .reduce((sum, s) => sum + s.duration_minutes, 0);
}

export function needsMoreThanOneDay(route: GeneratedRoute): boolean {
  return route.day_count_flag > 1;
}

/** What a history card leads with: the city is what a traveller recognises,
 *  the theme is the fallback. */
export function routeTitle(route: Pick<RouteSummary, "city_name" | "theme">): string {
  if (route.city_name) return route.city_name;
  if (!route.theme) return "Route";
  return route.theme[0].toUpperCase() + route.theme.slice(1);
}

/** `6 stops · 4h · Drive + walk` — the line under the title. */
export function routeSubtitle(route: RouteSummary): string {
  return [
    `${route.stop_count} ${route.stop_count === 1 ? "stop" : "stops"}`,
    formatMinutes(route.estimated_total_duration_minutes),
    transportLabel(route.transport_mode),
  ].join(" · ");
}

/** `today`, `3d`, `2w` — enough to place a route in time without a date format
 *  that would need locale rules this app does not have yet. */
export function relativeDay(iso: string | null): string | null {
  if (!iso) return null;
  const when = new Date(iso);
  if (Number.isNaN(when.getTime())) return null;
  const days = Math.floor((Date.now() - when.getTime()) / 86_400_000);
  if (days <= 0) return "today";
  if (days === 1) return "yesterday";
  if (days < 7) return `${days}d`;
  if (days < 365) return `${Math.floor(days / 7)}w`;
  return `${Math.floor(days / 365)}y`;
}

/** Copy for the failure codes the module returns, matching `AppBloc`'s. */
export function messageForCode(code: string, fallback?: string | null): string {
  switch (code) {
    case "city_not_available":
      return "This city isn't open for routes yet.";
    case "no_eligible_pois":
      return "No published stops match that theme here yet.";
    case "time_budget_too_short":
      return "That time budget is too short for any stop here.";
    case "rate_limited":
      return "You've generated a lot of routes just now. Try again shortly.";
    case "network_error":
      return "Couldn't reach the route service.";
    default:
      return fallback || "Something went wrong generating that route.";
  }
}
