/**
 * Layer 4 — Push Adapter. Wraps FCM (plan §6).
 *
 * Single interface: `send(tokens, payload)`. Fire-and-forget with retry;
 * failures are logged, never propagated — the orchestrator is what enforces
 * "never throws upward" (plan §3: "a push failure never fails a capture"),
 * by catching whatever this throws. See `orchestrator.ts`'s `notifyPush`.
 *
 * STATUS: implemented, by delegation. The send itself lives in
 * `src/notifications/adapters/fcmAdapter.ts` — this module's push is one of
 * three features that need FCM, and the other two (3D generation completion,
 * the "Notify me" toggle) are not AR at all, so the transport sits outside
 * `arCapture` and this interface stays as plan §7 specified it.
 */
import { sendPush } from "../../notifications/adapters/fcmAdapter";

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface PushAdapter {
  send(tokens: string[], payload: PushPayload): Promise<void>;
}

export class FcmPushAdapter implements PushAdapter {
  async send(tokens: string[], payload: PushPayload): Promise<void> {
    // `sendPush` already swallows its own failures and reports a count, so
    // there is nothing here to catch and nothing worth returning upward: this
    // interface's whole contract is that the caller cannot be affected.
    await sendPush(tokens, payload);
  }
}

let shared: PushAdapter | null = null;

export function getPushAdapter(): PushAdapter {
  if (shared === null) shared = new FcmPushAdapter();
  return shared;
}
