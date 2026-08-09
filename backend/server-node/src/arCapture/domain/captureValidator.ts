/**
 * Layer 3 — Capture Validator. Pure decision function, no dependencies.
 *
 * The ordered check list from plan §5.7, transcribed. The client is
 * untrusted — it knows the spawn coordinate, because it must to compute
 * distance offline, so a modified client can trivially claim to be standing
 * on it. This aims at *proportionate* deterrence, not a competitive-integrity
 * bar: a tourism stamp rally, not a competitive economy.
 *
 * Two checks from the plan's numbered list are NOT here:
 *   1. "spawn exists, belongs to req.routeId, state = 'active'" — everything
 *      up to "exists" is the caller's job (a nonexistent spawn never reaches
 *      this function; see `SpawnNotFoundError`), because `capture_outcome`
 *      (plan §7's schema) has no `not_found` member to return. "state is
 *      active" is folded into check 1 below instead.
 *   2. Idempotency ("client_nonce unseen, else return prior result") is a
 *      repository lookup, not a decision — the caller checks it before ever
 *      calling `validate` and returns the prior `CaptureValidationResult`
 *      directly if found.
 *
 * STATUS: implemented for real. Every input is already-hydrated data (the
 * plan's own signature: `spawn`, `request`, `history`, `now`), so this has no
 * Data or Adapter dependency despite living in a mostly-stubbed module.
 */
import { distanceMeters } from "../../routeGeneration/domain/clusteringEngine";
import type { Coordinate } from "../../routeGeneration/types";
import { CaptureOutcome, CaptureRequest, CaptureValidationResult, MascotSpawn } from "../types";
import type { CaptureTokenPayload } from "./captureToken";

/**
 * What `validate` needs of a spawn. `captureRadiusMeters` lives on
 * `ArContent` in the schema (one zone config shared by every spawn of that
 * POI), not on `MascotSpawn` itself — the caller joins it in rather than this
 * function taking a whole second row it would only read one field from.
 */
export type SpawnForValidation = Pick<MascotSpawn, "id" | "state" | "location"> & {
  captureRadiusMeters: number;
};

export interface CaptureHistory {
  /** An `accepted` capture already exists for this spawn (check 3 — not
   * necessarily by this user; the schema's partial unique index allows only
   * one accepted row per spawn regardless of who made it). */
  alreadyCaptured: boolean;
  /**
   * The decoded, signature-verified token the request's `captureToken`
   * resolved to (see `captureToken.ts`), or null if it failed verification
   * (check 6). Expiry is checked here against `now` rather than in
   * `verifyCaptureToken`, since only the caller knows what "now" means for a
   * possibly-replayed offline capture. `issuedFix` stands in for the plan's
   * geohash binding — see `captureToken.ts`'s module docstring.
   */
  token: CaptureTokenPayload | null;
  /** This user's most recently *accepted* capture, for the speed-plausibility
   * check (check 8). Null if this would be their first. */
  previousAccepted: { fix: Coordinate; clientTs: string } | null;
  /** This user's accepted-capture count in the last rolling hour (check 9). */
  acceptedCapturesInLastHour: number;
}

export const ACCURACY_GATE_METERS = 50;
export const CAPTURE_ACCURACY_SLACK_METERS = 35;
export const TOKEN_LOCATION_SLACK_METERS = 150;
export const CLOCK_SLACK_MS = 5 * 60 * 1000;
export const OFFLINE_REPLAY_WINDOW_MS = 24 * 60 * 60 * 1000;
export const IMPLAUSIBLE_SPEED_KMH = 120;
export const MAX_ACCEPTED_CAPTURES_PER_HOUR = 20;

function outcome(value: CaptureOutcome, flags: string[] = []): CaptureValidationResult {
  return { outcome: value, flags };
}

export function validate(
  spawn: SpawnForValidation,
  request: CaptureRequest,
  history: CaptureHistory,
  now: Date,
): CaptureValidationResult {
  // 1 (partial — existence is the caller's job). A spawn that isn't active
  // has necessarily already been captured or has expired; either way this
  // attempt cannot succeed, and 'already_captured' is the closer of the two
  // outcomes the schema actually has.
  if (spawn.state !== "active") return outcome("already_captured");

  // 3. Not already captured (by anyone — the DB enforces one accepted row
  // per spawn regardless of user, and this mirrors that here).
  if (history.alreadyCaptured) return outcome("already_captured");

  // 4. Accuracy gate.
  if (request.accuracyMeters > ACCURACY_GATE_METERS) return outcome("low_accuracy");

  // 5. Distance, generous toward the claimant (d_upper), since a spoofer
  // gets no more slack than an honest low-accuracy fix would need anyway.
  const rawDistance = distanceMeters(request.fix, spawn.location);
  const dUpper = rawDistance + Math.min(request.accuracyMeters, CAPTURE_ACCURACY_SLACK_METERS);
  if (dUpper > spawn.captureRadiusMeters) return outcome("too_far");

  // 6. Capture token: exists, matches this spawn/user, unexpired, and was
  // issued near where the capture claims to be happening now.
  const token = history.token;
  if (
    !token ||
    token.spawnId !== spawn.id ||
    token.userId !== request.userId ||
    new Date(token.expiresAt).getTime() < now.getTime() ||
    distanceMeters(token.issuedFix, request.fix) > TOKEN_LOCATION_SLACK_METERS
  ) {
    return outcome("invalid_token");
  }

  // 7. Timestamp plausibility — wider window for a queued offline capture.
  const clientTs = new Date(request.clientTs).getTime();
  const window = request.isOfflineReplay ? OFFLINE_REPLAY_WINDOW_MS : CLOCK_SLACK_MS;
  if (Math.abs(now.getTime() - clientTs) > window) return outcome("stale");

  // 8. Implied-speed plausibility. Flagged, not blocked — a legitimate user
  // on a fast road between two distant clusters (the route module's own
  // hybrid driving design) shouldn't be punished by a runtime block that
  // could embarrass a live jury walkthrough. Flags accumulate for offline
  // review instead.
  const flags: string[] = [];
  if (history.previousAccepted) {
    const previousTs = new Date(history.previousAccepted.clientTs).getTime();
    const elapsedHours = Math.abs(clientTs - previousTs) / (60 * 60 * 1000);
    if (elapsedHours > 0) {
      const traveled = distanceMeters(history.previousAccepted.fix, request.fix);
      const impliedKmh = traveled / 1000 / elapsedHours;
      if (impliedKmh > IMPLAUSIBLE_SPEED_KMH) flags.push("implausible_speed");
    }
  }

  // 9. Rate limit.
  if (history.acceptedCapturesInLastHour >= MAX_ACCEPTED_CAPTURES_PER_HOUR) {
    return outcome("rate_limited");
  }

  return outcome("accepted", flags);
}
