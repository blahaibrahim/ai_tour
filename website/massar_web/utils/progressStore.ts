/**
 * Where a walk in progress is remembered between page loads.
 *
 * Two facts, kept apart on purpose:
 *
 *   * the **progress id** the server issued, so checkpoints can be posted
 *     against the same record after a reload;
 *   * which **stop** the traveller says they are on, which the server has no
 *     column for — `route_progress` records arrivals, not a cursor.
 *
 * Both are per-route and live in `localStorage`, because losing them should
 * cost the walk nothing worse than starting the list again from the top. The
 * phone app keeps the same pair in its restored session.
 */

const PROGRESS_KEY = (routeId: string) => `massar_progress_${routeId}`;
const CURSOR_KEY = (routeId: string) => `massar_stop_${routeId}`;

function read(key: string): string | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage.getItem(key);
  } catch {
    // Storage can be denied outright — a private window with cookies blocked,
    // for one. The walk works without it; only the resume does not.
    return null;
  }
}

function write(key: string, value: string) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(key, value);
  } catch {
    /* see `read` */
  }
}

export function rememberProgressId(routeId: string, progressId: string) {
  write(PROGRESS_KEY(routeId), progressId);
}

export function readProgressId(routeId: string): string | null {
  return read(PROGRESS_KEY(routeId));
}

/**
 * Subscribers to the cursor, so `useSyncExternalStore` can treat it as what it
 * is: state owned by the browser rather than by React.
 *
 * Two sources of change, and both matter. `rememberCurrentStop` covers this
 * tab; the `storage` event covers the others, so a route open twice does not
 * end up with two different ideas of where the traveller is.
 */
const listeners = new Set<() => void>();

export function rememberCurrentStop(routeId: string, index: number) {
  write(CURSOR_KEY(routeId), String(index));
  listeners.forEach((notify) => notify());
}

export function readCurrentStop(routeId: string): number {
  const raw = read(CURSOR_KEY(routeId));
  const index = raw === null ? 0 : Number.parseInt(raw, 10);
  return Number.isFinite(index) && index >= 0 ? index : 0;
}

/**
 * Before the first paint on the server there is no browser to ask, and the
 * honest answer is the start of the route. React renders this during
 * hydration and then swaps in the real position, so a resumed walk shows stop
 * one for a frame — which is the correct trade against markup that does not
 * match what the server sent.
 */
export function readCurrentStopOnServer(): number {
  return 0;
}

export function subscribeToCurrentStop(onChange: () => void): () => void {
  listeners.add(onChange);
  window.addEventListener("storage", onChange);
  return () => {
    listeners.delete(onChange);
    window.removeEventListener("storage", onChange);
  };
}

/** Forgets a walk entirely — the "leave this tour" exit in Settings. */
export function forgetRoute(routeId: string) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.removeItem(PROGRESS_KEY(routeId));
    window.localStorage.removeItem(CURSOR_KEY(routeId));
  } catch {
    /* see `read` */
  }
}

/**
 * Forgets every walk this browser is part-way through.
 *
 * Prefix-matched rather than tracked in an index: the keys are the record, and
 * a second list of which routes have one is a thing that can fall out of step
 * with them. The routes themselves are untouched — this clears where you had
 * got to, not what was planned.
 */
export function forgetAllRoutes(): number {
  if (typeof window === "undefined") return 0;
  try {
    const keys = Object.keys(window.localStorage).filter(
      (key) => key.startsWith("massar_progress_") || key.startsWith("massar_stop_"),
    );
    keys.forEach((key) => window.localStorage.removeItem(key));
    // Two keys per route, and a route can have either without the other.
    return new Set(
      keys.map((key) => key.replace(/^massar_(progress|stop)_/, "")),
    ).size;
  } catch {
    return 0;
  }
}
