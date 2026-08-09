/**
 * AR Capture Module — shared contracts (docs/mascot_plan.md §7).
 *
 * Same rule as `routeGeneration/types.ts`: Layer 3 (Domain) is specified to be
 * pure, so nothing here imports a provider SDK, a database client, or an HTTP
 * framework. `Coordinate` is imported from `routeGeneration/types` rather than
 * redeclared — the plan reuses that module's Routing Provider and Cache
 * adapters directly (§3), so the two modules already share that shape.
 */
import type { Coordinate } from "../routeGeneration/types";

export type { Coordinate };

export type MascotRarity = "common" | "uncommon" | "rare" | "legendary";
export type SpawnState = "active" | "captured" | "expired";
export type CaptureOutcome =
  | "accepted"
  | "too_far"
  | "low_accuracy"
  | "already_captured"
  | "invalid_token"
  | "stale"
  | "rate_limited";
export type PlacementQuality = "plane_hit" | "plane_estimated" | "gyro_overlay" | "map_capture";
export type DevicePlatform = "android" | "ios" | "web";

/** Proximity bands, coldest to hottest (plan §5.3). Ordering matters — the
 * calculator compares which band is "closer" by array position. */
export const PROXIMITY_BANDS = ["frozen", "cold", "warm", "hot", "burning"] as const;
export type ProximityBand = (typeof PROXIMITY_BANDS)[number];

// --- data records (Layer 5 shapes) ------------------------------------------

export interface Mascot {
  id: string;
  key: string;
  nameFr: string;
  nameAr: string;
  nameEn: string;
  loreFr: string | null;
  loreAr: string | null;
  loreEn: string | null;
  rarity: MascotRarity;
  modelGlbRef: string;
  modelUsdzRef: string;
  modelChecksum: string;
  scaleMeters: number;
  thumbnailRef: string | null;
}

/** Distance boundaries between bands, metres. Defaults match plan §5.3's
 * table; `ArContent.bandThresholds` carries per-POI overrides. */
export interface BandThresholds {
  coldMeters: number;
  warmMeters: number;
  hotMeters: number;
  burningMeters: number;
}

export const DEFAULT_BAND_THRESHOLDS: BandThresholds = {
  coldMeters: 300,
  warmMeters: 150,
  hotMeters: 60,
  burningMeters: 25,
};

export interface ArContent {
  id: string;
  poiId: string;
  mascotId: string;
  /** GeoJSON-style polygon ring(s), curated per plan §5.1 — never a raw
   * radius, because that can drop a mascot in traffic. */
  spawnZone: Array<Array<[number, number]>>;
  spawnRadiusMeters: number;
  captureRadiusMeters: number;
  hotRadiusMeters: number;
  bandThresholds: Partial<BandThresholds>;
  presentationDistanceMeters: number;
  isEnabled: boolean;
  zoneReviewedBy: string | null;
}

export interface MascotSpawn {
  id: string;
  routeId: string;
  poiId: string;
  arContentId: string;
  mascotId: string;
  location: Coordinate;
  spawnSeed: string;
  spawnEpoch: string; // ISO date, coarse time bucket (plan §5.1)
  state: SpawnState;
  expiresAt: string | null;
  createdAt: string;
}

export interface MascotCapture {
  id: string;
  spawnId: string;
  userId: string | null;
  clientNonce: string;
  outcome: CaptureOutcome;
  deviceFix: Coordinate | null;
  fixAccuracyM: number | null;
  measuredDistanceM: number | null;
  placement: PlacementQuality | null;
  arTelemetry: Record<string, unknown>;
  flags: string[];
  clientTs: string;
  isOfflineReplay: boolean;
  createdAt: string;
}

export interface CollectionEntry {
  id: string;
  userId: string;
  mascotId: string;
  firstCapturedAt: string;
  captureCount: number;
}

export interface PushToken {
  id: string;
  userId: string;
  token: string;
  platform: DevicePlatform;
  arCapability: string | null;
  lastSeenAt: string;
}

// --- domain shapes (Layer 3) -------------------------------------------------

/** One entry of the spawn manifest the client fetches once per route and
 * caches — plan §4 Flow A step 6. */
export interface SpawnManifestEntry {
  spawnId: string;
  poiId: string;
  location: Coordinate;
  captureRadiusMeters: number;
  hotRadiusMeters: number;
  bandThresholds: BandThresholds;
  presentationDistanceMeters: number;
  mascot: {
    id: string;
    key: string;
    name: string;
    rarity: MascotRarity;
    modelGlbUrl: string;
    modelUsdzUrl: string;
    modelChecksum: string;
    scaleMeters: number;
  };
}

export interface SpawnManifest {
  routeId: string;
  spawns: SpawnManifestEntry[];
}

export interface CaptureRequest {
  spawnId: string;
  userId: string;
  captureToken: string;
  fix: Coordinate;
  accuracyMeters: number;
  clientTs: string;
  clientNonce: string;
  arTelemetry: Record<string, unknown>;
  isOfflineReplay?: boolean;
}

export interface CaptureValidationResult {
  outcome: CaptureOutcome;
  flags: string[];
}

export interface ProximityClaim {
  spawnId: string;
  userId: string;
  fix: Coordinate;
  accuracyMeters: number;
}

export interface CaptureToken {
  token: string;
  expiresAt: string;
}

export interface NotificationPrefs {
  quietHoursStart: number; // local hour, 0-23
  quietHoursEnd: number;
  optedOut: boolean;
}

export interface NotificationLogEntry {
  spawnId: string;
  sentAt: string;
}

export interface Reward {
  points: number;
  isFirstCatch: boolean;
}
