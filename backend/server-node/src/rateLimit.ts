import * as crypto from "crypto";

import type { User } from "@supabase/supabase-js";
import type { Request } from "express";

import { getUserClient } from "./data/supabaseClient";
import { getAdminClient } from "./ingestion/supabaseAdmin";
import { getLogger } from "./logger";
import { unwrap } from "./supabase";

const logger = getLogger("rateLimit");

/**
 * Verified-JWT cache.
 *
 * Every authenticated route paid a client construction plus a network round
 * trip to GoTrue's /user on *every* request, and the client polls
 * /api/itinerary/job/:id once a second while a route generates — so a single
 * route generation spent more wall time re-verifying the same token than the
 * work it was polling for. Access tokens are valid for an hour; re-checking one
 * every 60 s is the same guarantee at a fraction of the cost, and a revoked
 * session still stops working within the window.
 *
 * The `threading.Lock` the Python version needed is gone: a single-threaded
 * event loop gives the same guarantee for free.
 */
const JWT_TTL_MS = 60_000;
const jwtCache = new Map<string, { storedAt: number; user: User }>();

async function cachedUser(jwt: string): Promise<User | null> {
  const key = crypto.createHash("sha256").update(jwt).digest("hex");
  const now = Date.now();

  const entry = jwtCache.get(key);
  if (entry && now - entry.storedAt < JWT_TTL_MS) {
    return entry.user;
  }

  const userClient = getUserClient(jwt);

  let user: User | null;
  try {
    const { data, error } = await userClient.auth.getUser(jwt);
    if (error) throw error;
    user = data.user;
  } catch (error) {
    logger.exception("Failed to getUser with provided JWT.", error);
    return null;
  }

  if (user === null) {
    return null;
  }

  // Expired entries are only ever evicted here, which is fine: the key
  // space is one entry per active session, not per request.
  if (jwtCache.size > 512) {
    for (const [staleKey, staleEntry] of jwtCache) {
      if (now - staleEntry.storedAt >= JWT_TTL_MS) jwtCache.delete(staleKey);
    }
  }
  jwtCache.set(key, { storedAt: now, user });
  return user;
}

export interface AuthFailure {
  status: number;
  body: Record<string, unknown>;
}

export type AuthResult =
  | { user: User; failure: null }
  | { user: null; failure: AuthFailure };

/** The raw `Authorization: Bearer <jwt>` token, or null if absent/malformed. */
export function bearerToken(req: Request): string | null {
  const header = req.header("Authorization");
  if (!header || !header.startsWith("Bearer ")) return null;
  return header.slice("Bearer ".length);
}

/**
 * Validates the Bearer JWT from the Authorization header and checks rate limit.
 *
 * Returns `{user, failure: null}` if authenticated and within rate limit, or
 * `{user: null, failure}` with the status and body the route should answer.
 */
export async function authenticateAndRateLimit(
  req: Request,
  action: string,
  maxRequests: number,
  window: string,
): Promise<AuthResult> {
  const jwt = bearerToken(req);
  if (jwt === null) {
    logger.warning(
      `Missing or invalid Authorization header. Header value: ${req.header("Authorization")}`,
    );
    return { user: null, failure: { status: 401, body: { error: "unauthorized" } } };
  }

  const user = await cachedUser(jwt);
  if (!user) {
    return { user: null, failure: { status: 401, body: { error: "unauthorized" } } };
  }

  try {
    const admin = getAdminClient();
    const allowed = await unwrap(
      admin.rpc("check_rate_limit", {
        p_user: user.id,
        p_action: action,
        p_max: maxRequests,
        p_window: window,
      }),
    );

    if (!allowed) {
      return {
        user: null,
        failure: {
          status: 429,
          body: { error: "rate_limit_exceeded", message: `Rate limit exceeded for ${action}` },
        },
      };
    }
  } catch {
    // If DB rate limit check raises (e.g. table issue in test env), fail open
    // gracefully — same as the Python.
  }

  return { user, failure: null };
}
