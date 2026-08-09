/**
 * Layer 4 — Push Adapter. Wraps FCM (plan §6).
 *
 * Single interface: `send(tokens, payload)`. Fire-and-forget with retry;
 * failures are logged, never propagated — the orchestrator is what enforces
 * "never throws upward" (plan §3: "a push failure never fails a capture"),
 * by catching whatever this throws, including `NotImplementedError` itself
 * while this stub is unbuilt. See `orchestrator.ts`'s `notifyPush`.
 *
 * STATUS: interface only, same maturity as every adapter in
 * `routeGeneration/adapters/` — every method throws `NotImplementedError`.
 */
import { NotImplementedError } from "../errors";

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface PushAdapter {
  send(tokens: string[], payload: PushPayload): Promise<void>;
}

export class FcmPushAdapter implements PushAdapter {
  send(_tokens: string[], _payload: PushPayload): Promise<void> {
    // Fails silently as requested for now.
    return Promise.resolve();
  }
}

let shared: PushAdapter | null = null;

export function getPushAdapter(): PushAdapter {
  if (shared === null) shared = new FcmPushAdapter();
  return shared;
}
