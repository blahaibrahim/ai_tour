/**
 * Layer 3 — Collection Service. Pure projection, no dependencies.
 *
 * First-catch detection, rarity rollup, album projection (plan §3). The
 * caller is responsible for persisting the returned `entry` and for emitting
 * the checkpoint arrival this deployment represents as `trip_stops`/task
 * completion rather than the plan's `progress_events` — see the module
 * README's deviations table.
 *
 * STATUS: implemented for real — pure arithmetic over the caller's data, no
 * Data or Adapter dependency.
 */
import * as crypto from "crypto";

import { CollectionEntry, MascotRarity, Reward } from "../types";

export interface AcceptedCapture {
  userId: string;
  mascotId: string;
  capturedAt: string;
}

/**
 * NOT IN SPEC — plan §7's `Reward` type has no named point values per
 * rarity. This mirrors the client's existing task-point convention (30 pts
 * default, see `lib/blocs/app/app_bloc.dart`'s `AcceptRouteEvent` handler)
 * scaled by rarity, so a legendary catch is worth noticeably more than a
 * common one without inventing an unrelated currency.
 */
export const REWARD_POINTS: Record<MascotRarity, number> = {
  common: 30,
  uncommon: 50,
  rare: 80,
  legendary: 150,
};

export function applyCapture(
  capture: AcceptedCapture,
  existing: CollectionEntry | null,
  mascotRarity: MascotRarity,
): { entry: CollectionEntry; isFirstCatch: boolean; reward: Reward } {
  const isFirstCatch = existing === null;

  const entry: CollectionEntry = existing
    ? { ...existing, captureCount: existing.captureCount + 1 }
    : {
        id: crypto.randomUUID(),
        userId: capture.userId,
        mascotId: capture.mascotId,
        firstCapturedAt: capture.capturedAt,
        captureCount: 1,
      };

  return {
    entry,
    isFirstCatch,
    reward: { points: REWARD_POINTS[mascotRarity], isFirstCatch },
  };
}
