/**
 * The real FCM sender — the implementation `arCapture/adapters/pushAdapter.ts`
 * declared and stubbed out.
 *
 * Two properties the callers depend on:
 *
 *   * **It never throws.** `send` resolves with a count, whatever happened.
 *     A push is a courtesy layered on top of an operation that already
 *     succeeded (docs/mascot_plan.md §3: "a push failure never fails a
 *     capture"), and the same holds for a 3D job that has already finished.
 *   * **It prunes.** FCM answers `registration-token-not-registered` for a
 *     token belonging to an uninstalled app, and it will answer that forever.
 *     Deleting on that specific error is the only thing that keeps
 *     `push_tokens` from filling with tombstones that are retried on every
 *     send for the life of the deployment.
 *
 * Unconfigured is a supported state: with no service account in the
 * environment this logs once and reports zero delivered, so the rest of the
 * backend runs normally on a machine that has no Firebase credentials.
 */
import * as fs from "fs";
import * as path from "path";

import { BACKEND_DIR, Config } from "../../config";
import { getAdminClient } from "../../ingestion/supabaseAdmin";
import { getLogger } from "../../logger";
import { PushPayload } from "../types";

const logger = getLogger("notifications.fcm");

/** Structural subset of firebase-admin, so this file type-checks and the
 * project builds before anyone runs `npm install firebase-admin`. The import
 * is dynamic for the same reason. */
interface FirebaseMessaging {
  sendEachForMulticast(message: unknown): Promise<{
    successCount: number;
    responses: { success: boolean; error?: { code?: string } }[];
  }>;
}

type MessagingFactory = () => FirebaseMessaging;

let messaging: FirebaseMessaging | null = null;
let initialized = false;

// `undefined` means "not attempted yet". Cached (rather than re-read per
// call) so `isPushConfigured()` can answer synchronously from the same
// result `getMessaging()` uses, instead of only checking that the env var
// string is non-empty — which was true even while the credential file could
// not actually be read, masking that failure from both logs and the
// `push_configured` field the app reads.
let cachedServiceAccount: Record<string, unknown> | null | undefined;

/** The service account, from either an inline JSON blob or a path to a file.
 * Both forms exist because hosts differ: a container platform hands you an
 * environment variable, a VM hands you a file. */
function loadServiceAccount(): Record<string, unknown> | null {
  const inline = Config.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (inline) {
    try {
      return JSON.parse(inline) as Record<string, unknown>;
    } catch (error) {
      logger.exception("FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON", error);
      return null;
    }
  }

  const configuredPath = Config.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (configuredPath) {
    // A relative path is only meaningful relative to backend/ (where .env
    // lives), not to whatever the process's cwd happens to be — `npm run
    // dev` from backend/server-node makes those two different, and a path
    // that resolves against the wrong one fails silently (see BACKEND_DIR's
    // own comment in config.ts for why .env itself doesn't have this bug).
    const resolvedPath = path.isAbsolute(configuredPath)
      ? configuredPath
      : path.resolve(BACKEND_DIR, configuredPath);
    try {
      return JSON.parse(fs.readFileSync(resolvedPath, "utf8")) as Record<string, unknown>;
    } catch (error) {
      logger.exception(
        `Could not read FIREBASE_SERVICE_ACCOUNT_PATH (${configuredPath} -> ${resolvedPath})`,
        error,
      );
      return null;
    }
  }

  return null;
}

function getServiceAccount(): Record<string, unknown> | null {
  if (cachedServiceAccount === undefined) {
    cachedServiceAccount = loadServiceAccount();
  }
  return cachedServiceAccount;
}

async function getMessaging(): Promise<FirebaseMessaging | null> {
  if (initialized) return messaging;
  initialized = true;

  const serviceAccount = getServiceAccount();
  if (!serviceAccount) {
    if (!Config.FIREBASE_SERVICE_ACCOUNT_JSON && !Config.FIREBASE_SERVICE_ACCOUNT_PATH) {
      logger.warning(
        "Push notifications are disabled: neither FIREBASE_SERVICE_ACCOUNT_JSON nor " +
          "FIREBASE_SERVICE_ACCOUNT_PATH is set in backend/.env. " +
          "See docs/backend/15-notifications-and-fcm.md.",
      );
    }
    // Else: a var is set but the credential failed to load — already logged
    // with the specific reason by loadServiceAccount() above.
    return null;
  }

  try {
    // Dynamic so that a deployment which never sends push does not need the
    // dependency present at all.
    const admin = (await import("firebase-admin")) as unknown as {
      credential: { cert(account: unknown): unknown };
      initializeApp(options: { credential: unknown }): unknown;
      apps: unknown[];
      messaging: MessagingFactory;
    };
    if (admin.apps.length === 0) {
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    }
    messaging = admin.messaging();
    logger.info("FCM initialised.");
  } catch (error) {
    logger.exception(
      "Could not initialise firebase-admin. Run `npm install` in backend/server-node.",
      error,
    );
    messaging = null;
  }
  return messaging;
}

/** True when the deployment is capable of sending. Callers use it to skip the
 * policy and token lookups entirely rather than to decide correctness — an
 * unconfigured send is already a no-op.
 *
 * Actually loads/parses the credential (cached after the first call) rather
 * than only checking that an env var string is non-empty, so a bad path or
 * malformed JSON shows up here too, not just as a log line on first send. */
export function isPushConfigured(): boolean {
  if (!(Config.FIREBASE_SERVICE_ACCOUNT_JSON || Config.FIREBASE_SERVICE_ACCOUNT_PATH)) {
    return false;
  }
  return getServiceAccount() !== null;
}

/** FCM's verdict for a token that will never be valid again. Anything else —
 * a quota error, an outage, a malformed payload — is transient or our own
 * fault, and deleting the token over it would lose a live device. */
const DEAD_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

async function pruneTokens(tokens: string[]): Promise<void> {
  if (tokens.length === 0) return;
  try {
    await getAdminClient().from("push_tokens").delete().in("token", tokens);
    logger.info(`Pruned ${tokens.length} dead push token(s).`);
  } catch (error) {
    logger.exception("Could not prune dead push tokens (non-fatal)", error);
  }
}

/**
 * Sends [payload] to every token in [tokens]. Returns the number that were
 * accepted.
 *
 * Both a `notification` block and a `data` block go out, which is what gives
 * the client the behaviour the feature needs without any per-platform special
 * casing: while the app is backgrounded or terminated the OS renders the
 * `notification` block itself, and while it is in the foreground firebase_messaging
 * suppresses that and hands the `data` block to `onMessage`, where
 * `NotificationService` decides whether the UI is already saying it.
 */
export async function sendPush(tokens: string[], payload: PushPayload): Promise<number> {
  if (tokens.length === 0) return 0;

  const client = await getMessaging();
  if (!client) return 0;

  try {
    const response = await client.sendEachForMulticast({
      tokens,
      notification: { title: payload.title, body: payload.body },
      data: payload.data ?? {},
      android: {
        priority: "high",
        notification: {
          // Must match the channel NotificationService creates on the client.
          // Android silently drops a notification addressed to a channel that
          // does not exist, with nothing in logcat to say why.
          channelId: "massar_default",
          sound: "default",
        },
      },
      apns: {
        payload: { aps: { sound: "default", contentAvailable: true } },
      },
    });

    const dead: string[] = [];
    response.responses.forEach((result, i) => {
      if (result.success) return;
      const code = result.error?.code;
      if (code && DEAD_TOKEN_CODES.has(code)) dead.push(tokens[i]);
      else logger.warning(`Push to token ${i} failed: ${code ?? "unknown"}`);
    });
    await pruneTokens(dead);

    return response.successCount;
  } catch (error) {
    logger.exception("FCM send failed (non-fatal)", error);
    return 0;
  }
}
