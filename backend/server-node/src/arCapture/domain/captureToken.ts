/**
 * Layer 3 — capture tokens (plan §5.7).
 *
 * "A short-lived HMAC-signed token (TTL 5 min) bound to spawnId ‖ user ‖
 * issued_at ‖ fix_geohash." Self-verifying by construction, so unlike every
 * other piece of state in this module it needs no repository or table at
 * all: verification is signature-check-and-decode, not a lookup. This is
 * what lets `captureValidator.validate` stay pure — the token is just more
 * already-hydrated input, exactly like `history.token`.
 *
 * The `fix_geohash` binding is a plain coordinate here rather than an actual
 * geohash — see `captureValidator.ts`'s note on `CaptureTokenPayload.issuedFix`.
 *
 * STATUS: implemented for real, no dependency beyond Node's `crypto`.
 */
import * as crypto from "crypto";

import type { Coordinate } from "../../routeGeneration/types";
import type { CaptureToken } from "../types";

export interface CaptureTokenPayload {
  spawnId: string;
  userId: string;
  issuedFix: Coordinate;
  issuedAt: string;
  expiresAt: string;
}

export const CAPTURE_TOKEN_TTL_SECONDS = 5 * 60;

export function issueCaptureToken(
  claim: { spawnId: string; userId: string; fix: Coordinate },
  serverSecret: string,
  now: Date,
  ttlSeconds: number = CAPTURE_TOKEN_TTL_SECONDS,
): CaptureToken {
  const payload: CaptureTokenPayload = {
    spawnId: claim.spawnId,
    userId: claim.userId,
    issuedFix: claim.fix,
    issuedAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + ttlSeconds * 1000).toISOString(),
  };
  const encoded = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = sign(encoded, serverSecret);
  return { token: `${encoded}.${signature}`, expiresAt: payload.expiresAt };
}

/** Decodes and signature-checks a token. Returns null on any tamper, bad
 * shape, or unparseable payload — callers treat null exactly like an
 * `invalid_token` outcome (plan §5.7 check 6); expiry is checked separately
 * by the caller against `now`, since only it knows what "now" means for a
 * possibly-replayed offline capture. */
export function verifyCaptureToken(
  token: string,
  serverSecret: string,
): CaptureTokenPayload | null {
  const separator = token.lastIndexOf(".");
  if (separator < 0) return null;
  const encoded = token.slice(0, separator);
  const signature = token.slice(separator + 1);

  if (!timingSafeEqual(signature, sign(encoded, serverSecret))) return null;

  try {
    const payload = JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
    if (
      typeof payload?.spawnId !== "string" ||
      typeof payload?.userId !== "string" ||
      typeof payload?.issuedFix?.lat !== "number" ||
      typeof payload?.issuedFix?.lng !== "number" ||
      typeof payload?.issuedAt !== "string" ||
      typeof payload?.expiresAt !== "string"
    ) {
      return null;
    }
    return payload as CaptureTokenPayload;
  } catch {
    return null;
  }
}

function sign(encoded: string, serverSecret: string): string {
  return crypto.createHmac("sha256", serverSecret).update(encoded).digest("base64url");
}

function timingSafeEqual(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}
