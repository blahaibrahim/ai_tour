/**
 * The module's public face — the only thing Layer 1 (`routes/mascots.ts`) is
 * allowed to import. Same fixture/real switch as `routeGeneration/index.ts`,
 * for the same reason: while `AR_CAPTURE_MODE=fixture` (the default) every
 * call here answers from `fixtures.ts`; set it to `real` and calls go to the
 * orchestrator, which throws `NotImplementedError` at the first missing Data
 * or Adapter piece — everything in `domain/` is real either way (see each
 * domain file's own STATUS note).
 */
import { getLogger } from "../logger";
import { getAssetStoreAdapter } from "./adapters/assetStoreAdapter";
import { getArContentRepository } from "./data/arContentRepository";
import { getCollectionRepository } from "./data/collectionRepository";
import { getMascotRepository } from "./data/mascotRepository";
import { getMascotSpawnRepository } from "./data/mascotSpawnRepository";
import { getPushTokenRepository } from "./data/pushTokenRepository";
import { issueCaptureToken } from "./domain/captureToken";
import { MascotNotFoundError, SpawnNotFoundError } from "./errors";
import {
  FIXTURE_AR_CONTENT,
  FIXTURE_MASCOT,
  fixtureManifest,
  fixtureSpawn,
} from "./fixtures";
import * as orchestrator from "./orchestrator";
import type { CaptureResponse } from "./orchestrator";
import {
  CaptureRequest,
  CaptureToken,
  CollectionEntry,
  Coordinate,
  DevicePlatform,
  PushToken,
  SpawnManifest,
} from "./types";

const logger = getLogger("arCapture");

export type ArCaptureMode = "fixture" | "real";

export const MODE: ArCaptureMode = process.env.AR_CAPTURE_MODE === "real" ? "real" : "fixture";

if (MODE === "fixture") {
  logger.warning(
    "AR CAPTURE IS SERVING FIXTURES. The module's Data layer is a skeleton — " +
      "see src/arCapture/README.md. Set AR_CAPTURE_MODE=real once it's implemented.",
  );
}

/** Never touches `AR_CAPTURE_TOKEN_SECRET`, so fixture mode works with no
 * env configuration at all — the same reason `fixtures.ts` hands back
 * `example.invalid` asset URLs rather than calling the (stub) asset store. */
const FIXTURE_TOKEN_SECRET = "fixture-mode-token-secret-not-for-production";

export async function generateManifest(routeId: string): Promise<SpawnManifest> {
  if (MODE === "fixture") return fixtureManifest(routeId);
  return orchestrator.generateManifest(routeId);
}

/**
 * `GET /v1/routes/:routeId/mascots` — rehydrates the manifest for spawns that
 * already exist, rather than `generateManifest`'s "create if missing" (plan
 * §6: "cached, ETag"). Reads each spawn's own `ar_content`/mascot rather than
 * re-deriving them from the route's current stops, so an already-issued
 * manifest keeps answering the same shape even if the route's AR content
 * changes later.
 *
 * NOT IN SPEC — plan §4 step 6 caches the assembled manifest via the
 * (reused) Cache Adapter; that adapter's interface is specific to route
 * matrices/isochrones today (`routeGeneration/adapters/cacheAdapter.ts`).
 * Re-assembling on every call here is correct but uncached until that
 * interface grows a generic slot, or this module gets its own.
 */
export async function getManifest(routeId: string): Promise<SpawnManifest> {
  if (MODE === "fixture") return fixtureManifest(routeId);

  const spawns = await getMascotSpawnRepository().findActiveByRoute(routeId);
  const arContentRepo = getArContentRepository();
  const mascotRepo = getMascotRepository();

  const entries = [];
  for (const spawn of spawns) {
    const arContent = await arContentRepo.findById(spawn.arContentId);
    const mascot = await mascotRepo.findById(spawn.mascotId);
    if (!arContent || !mascot) continue;
    entries.push(await orchestrator.assembleManifestEntry(spawn, arContent, mascot));
  }
  return { routeId, spawns: entries };
}

export async function issueProximityToken(
  spawnId: string,
  userId: string,
  fix: Coordinate,
  accuracyMeters: number,
): Promise<CaptureToken> {
  if (MODE === "fixture") {
    const spawn = fixtureSpawn("fixture");
    if (spawnId !== spawn.id) throw new SpawnNotFoundError(spawnId);
    return issueCaptureToken({ spawnId, userId, fix }, FIXTURE_TOKEN_SECRET, new Date());
  }
  return orchestrator.issueProximityToken(spawnId, userId, fix, accuracyMeters);
}

export async function submitCapture(request: CaptureRequest): Promise<CaptureResponse> {
  if (MODE === "fixture") {
    return {
      outcome: "accepted",
      reward: { points: 30, isFirstCatch: true },
      isFirstCatch: true,
      collection: { mascotId: FIXTURE_MASCOT.id, captureCount: 1 },
    };
  }
  return orchestrator.submitCapture(request);
}

export async function getCollection(userId: string): Promise<CollectionEntry[]> {
  if (MODE === "fixture") {
    return [
      {
        id: "b4000000-0000-4000-8000-000000000001",
        userId,
        mascotId: FIXTURE_MASCOT.id,
        firstCapturedAt: new Date().toISOString(),
        captureCount: 1,
      },
    ];
  }
  return getCollectionRepository().findAllForUser(userId);
}

export interface MascotAsset {
  glbUrl: string;
  usdzUrl: string;
  checksum: string;
}

/** `GET /v1/mascots/:mascotId/asset` (plan §6): a time-limited signed URl
 * plus checksum, resolved fresh on every call rather than cached in the
 * manifest — the manifest's `mascot.model*Url` fields are a snapshot from
 * whenever the manifest was assembled; this is for a client that needs a
 * fresh one after the original has expired. */
export async function getMascotAsset(mascotId: string): Promise<MascotAsset> {
  if (MODE === "fixture") {
    if (mascotId !== FIXTURE_MASCOT.id) throw new MascotNotFoundError(mascotId);
    return {
      glbUrl: "https://example.invalid/fixtures/fennec.glb",
      usdzUrl: "https://example.invalid/fixtures/fennec.usdz",
      checksum: FIXTURE_MASCOT.modelChecksum,
    };
  }
  const mascot = await getMascotRepository().findById(mascotId);
  if (!mascot) throw new MascotNotFoundError(mascotId);
  const assetStore = getAssetStoreAdapter();
  return {
    glbUrl: assetStore.getSignedUrl(mascot.modelGlbRef, 3600),
    usdzUrl: assetStore.getSignedUrl(mascot.modelUsdzRef, 3600),
    checksum: assetStore.getChecksum(mascot.modelGlbRef),
  };
}

export async function upsertPushToken(input: {
  userId: string;
  token: string;
  platform: DevicePlatform;
  arCapability: string | null;
}): Promise<PushToken> {
  if (MODE === "fixture") {
    return {
      id: "b5000000-0000-4000-8000-000000000001",
      userId: input.userId,
      token: input.token,
      platform: input.platform,
      arCapability: input.arCapability,
      lastSeenAt: new Date().toISOString(),
    };
  }
  return getPushTokenRepository().upsert(input);
}

export { FIXTURE_AR_CONTENT, FIXTURE_MASCOT };
export type { CaptureResponse } from "./orchestrator";
export * from "./types";
export {
  ArCaptureError,
  NotImplementedError,
  SpawnNotFoundError,
  MascotNotFoundError,
  RouteNotFoundError,
} from "./errors";
