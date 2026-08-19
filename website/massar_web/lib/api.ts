/**
 * Server-side client for the Route Generation API.
 *
 * Every call is authenticated with the caller's own Supabase access token, so
 * the Node service sees the same user the browser is signed in as and its RLS
 * and rate-limit buckets apply unchanged.
 *
 * Server Components only — it reaches for `cookies()`, which is what would stop
 * it importing cleanly into a client bundle. The browser goes through
 * `utils/apiFetch.ts` and the `/api/*` rewrite in `next.config.ts` instead.
 */

import { redirect } from "next/navigation";

import { createClient } from "@/utils/supabase/server";
import type {
  City,
  GeneratedRoute,
  RouteCategory,
  RouteSummary,
  RouteTheme,
} from "./types";

const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";

export interface Session {
  token: string;
  userId: string;
  email: string | null;
}

/**
 * The signed-in caller, or a redirect to the sign-in page.
 *
 * `getUser()` rather than `getSession()` alone for the identity: the session
 * is read straight out of a cookie and is only as trustworthy as that cookie,
 * while `getUser()` is validated against the auth server. The session is still
 * needed afterwards, but only for the access token it carries.
 */
export async function requireSession(): Promise<Session> {
  const supabase = await createClient();
  const [{ data: userData }, { data: sessionData }] = await Promise.all([
    supabase.auth.getUser(),
    supabase.auth.getSession(),
  ]);

  const user = userData.user;
  const token = sessionData.session?.access_token;
  if (!user || !token) redirect("/login");

  return { token, userId: user.id, email: user.email ?? null };
}

class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

async function get<T>(path: string, token: string): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    headers: { Authorization: `Bearer ${token}` },
    // Every one of these is per-user and changes the moment the traveller
    // generates something. There is nothing here worth a stale read.
    cache: "no-store",
  });

  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: string; message?: string };
    throw new ApiError(res.status, body.error ?? "server_error", body.message ?? res.statusText);
  }
  return (await res.json()) as T;
}

/** Cities, with the rollout status that says whether each can be routed. */
export async function fetchCities(token: string): Promise<City[]> {
  try {
    const data = await get<{ cities: City[] }>("/api/cities", token);
    return data.cities ?? [];
  } catch {
    return [];
  }
}

/** Themes and categories in one call — the planner needs both, and they change
 *  at the same rate. */
export async function fetchThemesAndCategories(
  token: string,
  cityId?: string,
): Promise<{ themes: RouteTheme[]; categories: RouteCategory[] }> {
  const query = cityId ? `?city_id=${encodeURIComponent(cityId)}` : "";
  try {
    const data = await get<{ themes: RouteTheme[]; categories: RouteCategory[] }>(
      `/api/categories${query}`,
      token,
    );
    return { themes: data.themes ?? [], categories: data.categories ?? [] };
  } catch {
    return { themes: [], categories: [] };
  }
}

/** The caller's own past routes, newest first. Empty rather than thrown: a
 *  history that failed to load should not take the home page down with it. */
export async function fetchMyRoutes(token: string, limit = 20): Promise<RouteSummary[]> {
  try {
    const data = await get<{ routes: RouteSummary[] }>(`/api/routes/mine?limit=${limit}`, token);
    return data.routes ?? [];
  } catch {
    return [];
  }
}

/** One route in full. Null when it does not exist or belongs to somebody else
 *  — the page turns that into its own empty state rather than a 500. */
export async function fetchRoute(token: string, routeId: string): Promise<GeneratedRoute | null> {
  try {
    return await get<GeneratedRoute>(`/api/routes/${routeId}`, token);
  } catch {
    return null;
  }
}
