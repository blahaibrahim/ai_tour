/**
 * The one thing this dashboard writes.
 *
 * `lib/supabase.ts` says in its own header that nothing in it writes, and that
 * is worth keeping true — it is the module holding the service-role key, and a
 * reader that cannot write is a much smaller thing to audit. So the two writes
 * publishing a splat needs live here instead:
 *
 *   1. **The object.** A decimated `.splatb` into the shared `splats` bucket
 *      (supabase/migrations/20260819120000). Any signed-in traveller may read
 *      that bucket; only service_role may fill it.
 *   2. **The notification.** Not written directly — handed to the app's own
 *      backend at `POST /api/internal/splat-notify`, which resolves the
 *      contributor's email, files the inbox row and sends the push.
 *
 * The second one is a round trip this module could technically skip: it holds a
 * key that can insert into `user_notifications` itself. It doesn't, because the
 * notification policy — quiet hours, the per-kind opt-out, the dedupe, the
 * wording — lives in `backend/server-node/src/notifications`, and a dashboard
 * that inserted its own rows would be a second implementation of all of it,
 * silently diverging the first time either side changed. This dashboard knows
 * about splats; the backend knows about notifying people.
 */
import { SUPABASE_SERVICE_ROLE_KEY, SUPABASE_URL } from "./config";

/** The app's backend — the same server the phone talks to. */
export const BACKEND_URL = (process.env.APP_BACKEND_URL ?? "").replace(/\/+$/, "");

/** Shared with the backend's `NOTIFY_HOOK_SECRET`. */
export const NOTIFY_HOOK_SECRET = process.env.NOTIFY_HOOK_SECRET ?? "";

export function notifyConfigured(): boolean {
  return Boolean(BACKEND_URL && NOTIFY_HOOK_SECRET);
}

export const NOTIFY_HINT =
  "set APP_BACKEND_URL and NOTIFY_HOOK_SECRET in .env.local. The secret is the " +
  "same value as NOTIFY_HOOK_SECRET in backend/server-node/.env — it is how the " +
  "backend tells this dashboard apart from the internet.";

/**
 * Uploads [bytes] to `splats/<key>`, replacing whatever was there.
 *
 * `x-upsert` rather than a delete-then-put: re-training a scene at a higher step
 * count and publishing again is the normal case, and the notification dedupes on
 * the storage path, so the object has to be replaceable in place or the second
 * publish would need a new path and would notify twice.
 */
export async function uploadSplat(key: string, bytes: Buffer): Promise<string> {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error(
      "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set to publish a splat",
    );
  }

  const response = await fetch(
    `${SUPABASE_URL}/storage/v1/object/splats/${encodeURI(key)}`,
    {
      method: "POST",
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        // The bucket's `allowed_mime_types` is exactly this. A `.splatb` is not
        // a registered type and never will be, so octet-stream is the honest
        // answer rather than an invented `application/x-splat`.
        "content-type": "application/octet-stream",
        "cache-control": "31536000",
        "x-upsert": "true",
      },
      body: new Uint8Array(bytes),
    },
  );

  if (!response.ok) {
    throw new Error(
      `upload failed: ${response.status} ${(await response.text()).slice(0, 200)}`,
    );
  }
  // Bucket-qualified, which is how every storage reference in this project's
  // database is stored and what the app's viewer expects to be handed.
  return `splats/${key}`;
}

export interface NotifyResult {
  userId: string;
  /** Devices the push reached. 0 is normal — the inbox row is filed either way. */
  delivered: number;
  /** Why no push went out, when that was a decision rather than a failure. */
  suppressedReason: string | null;
}

/** Asks the backend to tell [email]'s owner about a published splat. */
export async function notifyContributor(input: {
  email: string;
  scene: string;
  sceneTitle: string;
  splatPath: string;
  gaussians: number;
  poiId: string | null;
}): Promise<NotifyResult> {
  if (!notifyConfigured()) throw new Error(NOTIFY_HINT);

  const response = await fetch(`${BACKEND_URL}/api/internal/splat-notify`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-notify-secret": NOTIFY_HOOK_SECRET,
    },
    body: JSON.stringify({
      email: input.email,
      scene: input.scene,
      scene_title: input.sceneTitle,
      splat_path: input.splatPath,
      gaussians: input.gaussians,
      poi_id: input.poiId,
    }),
    cache: "no-store",
  });

  const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok) {
    // The backend's own error codes are more use to the operator than "502":
    // `no_such_user` means the email is wrong, `not_configured` means the
    // secret is missing on the *other* side.
    throw new Error(
      typeof payload.error === "string"
        ? `${payload.error}${payload.message ? `: ${payload.message}` : ""}`
        : `backend answered ${response.status}`,
    );
  }

  return {
    userId: String(payload.user_id ?? ""),
    delivered: Number(payload.delivered ?? 0) || 0,
    suppressedReason:
      typeof payload.suppressed_reason === "string" ? payload.suppressed_reason : null,
  };
}
