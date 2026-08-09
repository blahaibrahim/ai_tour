/**
 * Layer 2 — Mascot Session Orchestrator.
 *
 * Sequences Domain calls: manifest assembly on route start, the capture
 * validation pipeline, collection update, telemetry emission (plan §3).
 * Owns graceful degradation — a push failure never fails a capture, which is
 * why `notifyPush` swallows everything `PushAdapter.send` throws rather than
 * letting it propagate.
 *
 * STATUS: wired, like `routeGeneration/orchestrator.ts` — it calls through to
 * real domain logic where that exists (every function in `domain/`) and to
 * repository/adapter stubs where it does not, so it throws `NotImplementedError`
 * naming the first missing piece rather than failing silently or vaguely.
 */
import { requireArCaptureTokenSecret } from "../config";
import { getLogger } from "../logger";
import { distanceMeters } from "../routeGeneration/domain/clusteringEngine";
import * as routeGeneration from "../routeGeneration";
import { getAssetStoreAdapter } from "./adapters/assetStoreAdapter";
import { getPushAdapter, PushPayload } from "./adapters/pushAdapter";
import { getArContentRepository } from "./data/arContentRepository";
import { getCaptureRepository } from "./data/captureRepository";
import { getCollectionRepository } from "./data/collectionRepository";
import { getMascotRepository } from "./data/mascotRepository";
import { getMascotSpawnRepository } from "./data/mascotSpawnRepository";
import { applyCapture } from "./domain/collectionService";
import { CaptureHistory, SpawnForValidation, validate } from "./domain/captureValidator";
import { issueCaptureToken, verifyCaptureToken } from "./domain/captureToken";
import { deriveSpawnSeed, generateSpawnPoint } from "./domain/spawnPointGenerator";
import { ArCaptureError, RouteNotFoundError, SpawnNotFoundError } from "./errors";
import type { Coordinate } from "../routeGeneration/types";
import {
  ArContent,
  CaptureRequest,
  CaptureToken,
  CaptureValidationResult,
  Mascot,
  MascotSpawn,
  Reward,
  SpawnManifest,
  SpawnManifestEntry,
} from "./types";

const logger = getLogger("arCapture.orchestrator");

/**
 * Builds one manifest entry from an already-resolved spawn, its zone config
 * and its mascot. Shared by `generateManifest` (which creates the spawn
 * first) and `getManifest`'s real-mode path in `index.ts` (which reads
 * spawns that already exist) — the assembly step is identical either way.
 */
export async function assembleManifestEntry(
  spawn: MascotSpawn,
  arContent: ArContent,
  mascot: Pick<
    Mascot,
    "id" | "key" | "nameEn" | "rarity" | "modelGlbRef" | "modelUsdzRef" | "modelChecksum" | "scaleMeters"
  >,
): Promise<SpawnManifestEntry> {
  const assetStore = getAssetStoreAdapter();
  return {
    spawnId: spawn.id,
    poiId: spawn.poiId,
    location: spawn.location,
    captureRadiusMeters: arContent.captureRadiusMeters,
    hotRadiusMeters: arContent.hotRadiusMeters,
    bandThresholds: {
      coldMeters: arContent.bandThresholds.coldMeters ?? 300,
      warmMeters: arContent.bandThresholds.warmMeters ?? 150,
      hotMeters: arContent.bandThresholds.hotMeters ?? arContent.hotRadiusMeters,
      burningMeters: arContent.bandThresholds.burningMeters ?? arContent.captureRadiusMeters,
    },
    presentationDistanceMeters: arContent.presentationDistanceMeters,
    mascot: {
      id: mascot.id,
      key: mascot.key,
      name: mascot.nameEn,
      rarity: mascot.rarity,
      modelGlbUrl: assetStore.getSignedUrl(mascot.modelGlbRef, 3600),
      modelUsdzUrl: assetStore.getSignedUrl(mascot.modelUsdzRef, 3600),
      modelChecksum: mascot.modelChecksum,
      scaleMeters: mascot.scaleMeters,
    },
  };
}

/**
 * Flow A (plan §4, Figure 3): for each of the route's stops, load `ar_content`
 * for the POI — a route may be partially AR-enabled, so a stop with none is
 * silently skipped rather than failing the whole manifest — generate its
 * spawn point, persist it, and assemble the manifest the client caches for
 * the rest of the hunt.
 */
export async function generateManifest(routeId: string): Promise<SpawnManifest> {
  const route = await routeGeneration.getRoute(routeId, null).catch((error) => {
    if (error instanceof routeGeneration.RouteGenerationError && error.code === "route_not_found") {
      throw new RouteNotFoundError(routeId);
    }
    throw error;
  });

  const arContentRepo = getArContentRepository();
  const spawnRepo = getMascotSpawnRepository();
  const mascotRepo = getMascotRepository();
  const secret = requireArCaptureTokenSecret();
  const spawnEpoch = new Date().toISOString().slice(0, 10);

  const entries: SpawnManifestEntry[] = [];

  for (const stop of route.stops) {
    const arContent = await arContentRepo.findByPoiId(stop.poiId);
    if (!arContent || !arContent.isEnabled) continue;

    const seed = deriveSpawnSeed(secret, routeId, stop.poiId, spawnEpoch);
    const location = generateSpawnPoint(arContent.spawnZone, seed);

    const spawn = await spawnRepo.persist({
      routeId,
      poiId: stop.poiId,
      arContentId: arContent.id,
      mascotId: arContent.mascotId,
      location,
      spawnSeed: seed.toString("hex"),
      spawnEpoch,
      state: "active",
      expiresAt: null,
    });

    const mascot = await mascotRepo.findById(arContent.mascotId);
    if (!mascot) {
      logger.warning(`ar_content ${arContent.id} references missing mascot ${arContent.mascotId}`);
      continue;
    }

    entries.push(await assembleManifestEntry(spawn, arContent, mascot));
  }

  logger.info(`manifest for route ${routeId}: ${entries.length} spawn(s)`);
  return { routeId, spawns: entries };
}

/** Loads a spawn plus the `ar_content` fields the validator needs joined in
 * (plan §5.7's checks need `capture_radius_meters`, which lives on the zone
 * config, not the spawn row — see `SpawnForValidation`'s note). */
async function loadSpawnForValidation(
  spawnId: string,
): Promise<{ spawn: MascotSpawn; arContent: ArContent }> {
  const spawn = await getMascotSpawnRepository().findById(spawnId);
  if (!spawn) throw new SpawnNotFoundError(spawnId);
  const arContent = await getArContentRepository().findById(spawn.arContentId);
  if (!arContent) throw new SpawnNotFoundError(spawnId);
  return { spawn, arContent };
}

/**
 * Flow C step 2 (plan §5.7): the client's first verified proximity claim at a
 * real timestamp, gating a signed capture token. Rejects outright if the fix
 * isn't within the capture radius — no point minting a token that
 * `captureValidator` would reject on distance a moment later.
 */
export async function issueProximityToken(
  spawnId: string,
  userId: string,
  fix: Coordinate,
  accuracyMeters: number,
): Promise<CaptureToken> {
  const { spawn, arContent } = await loadSpawnForValidation(spawnId);
  if (spawn.state !== "active") {
    throw new ArCaptureError("already_captured", 409, `Spawn ${spawnId} is no longer active.`);
  }

  const distance = distanceMeters(fix, spawn.location);
  const upperBound = distance + Math.min(accuracyMeters, 35);
  if (upperBound > arContent.captureRadiusMeters) {
    throw new ArCaptureError(
      "too_far",
      422,
      `Fix is ${Math.round(distance)}m from the spawn; capture radius is ${arContent.captureRadiusMeters}m.`,
    );
  }

  return issueCaptureToken({ spawnId, userId, fix }, requireArCaptureTokenSecret(), new Date());
}

export interface CaptureResponse {
  outcome: CaptureValidationResult["outcome"];
  reward: Reward | null;
  isFirstCatch: boolean;
  collection: { mascotId: string; captureCount: number } | null;
}

/**
 * Flow C steps 7-9 (plan §4, §5.7): hydrate the validator's inputs, run the
 * pure check list, persist the attempt (accepted or not — this repository is
 * append-only by design), and on acceptance update the collection and mark
 * the spawn captured. A push notification, if any is ever wired to fire
 * here, is fire-and-forget via `notifyPush` and cannot fail this call.
 */
export async function submitCapture(request: CaptureRequest): Promise<CaptureResponse> {
  const captureRepo = getCaptureRepository();

  const prior = await captureRepo.findByNonce(request.clientNonce);
  if (prior) {
    return {
      outcome: prior.outcome,
      reward: null,
      isFirstCatch: false,
      collection: null,
    };
  }

  const { spawn, arContent } = await loadSpawnForValidation(request.spawnId);

  const now = new Date();
  const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);
  const tokenPayload = verifyCaptureToken(request.captureToken, requireArCaptureTokenSecret());

  const history: CaptureHistory = {
    alreadyCaptured: await captureRepo.hasAcceptedCapture(spawn.id),
    token: tokenPayload,
    previousAccepted: await captureRepo.findLastAccepted(request.userId),
    acceptedCapturesInLastHour: await captureRepo.countAcceptedSince(request.userId, oneHourAgo),
  };

  const spawnForValidation: SpawnForValidation = {
    id: spawn.id,
    state: spawn.state,
    location: spawn.location,
    captureRadiusMeters: arContent.captureRadiusMeters,
  };

  const result = validate(spawnForValidation, request, history, now);

  await captureRepo.insert({
    spawnId: spawn.id,
    userId: request.userId,
    clientNonce: request.clientNonce,
    outcome: result.outcome,
    deviceFix: request.fix,
    fixAccuracyM: request.accuracyMeters,
    measuredDistanceM: null,
    placement: null,
    arTelemetry: request.arTelemetry,
    flags: result.flags,
    clientTs: request.clientTs,
    isOfflineReplay: request.isOfflineReplay ?? false,
  });

  if (result.outcome !== "accepted") {
    return { outcome: result.outcome, reward: null, isFirstCatch: false, collection: null };
  }

  await getMascotSpawnRepository().markCaptured(spawn.id);

  const collectionRepo = getCollectionRepository();
  const mascot = await getMascotRepository().findById(spawn.mascotId);
  const existing = mascot
    ? await collectionRepo.findByUserAndMascot(request.userId, mascot.id)
    : null;

  if (!mascot) {
    logger.warning(`spawn ${spawn.id} references missing mascot ${spawn.mascotId}`);
    return { outcome: "accepted", reward: null, isFirstCatch: false, collection: null };
  }

  const { entry, isFirstCatch, reward } = applyCapture(
    { userId: request.userId, mascotId: mascot.id, capturedAt: now.toISOString() },
    existing,
    mascot.rarity,
  );
  await collectionRepo.upsert(entry);

  return {
    outcome: "accepted",
    reward,
    isFirstCatch,
    collection: { mascotId: entry.mascotId, captureCount: entry.captureCount },
  };
}

/** Fire-and-forget wrapper the plan requires (§3): "a push failure never
 * fails a capture." Every caller of `PushAdapter.send` goes through this
 * instead of calling the adapter directly. */
export async function notifyPush(tokens: string[], payload: PushPayload): Promise<void> {
  if (tokens.length === 0) return;
  try {
    await getPushAdapter().send(tokens, payload);
  } catch (error) {
    logger.exception("Push notification failed (non-fatal)", error);
  }
}

/** Not spec-numbered, but named directly in plan §5.1: "the spawn is
 * reproducible for debugging a support report." Recomputes the seed and
 * point for one POI without touching the spawn table, so a support ticket
 * can be checked against what the client says it saw. */
export function debugRecomputeSpawn(
  routeId: string,
  poiId: string,
  spawnEpoch: string,
  zone: ArContent["spawnZone"],
): { seedHex: string; location: Coordinate } {
  const seed = deriveSpawnSeed(requireArCaptureTokenSecret(), routeId, poiId, spawnEpoch);
  return { seedHex: seed.toString("hex"), location: generateSpawnPoint(zone, seed) };
}
