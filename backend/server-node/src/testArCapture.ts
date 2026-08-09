/**
 * Regression checks for the AR capture module's pure domain layer.
 *
 *     npm test
 *
 * Kept in the same zero-dependency style as `testPoiRules.ts` (no vitest
 * here either) — a `check(label, got, expected)` harness that collects
 * failures and exits 1 if any survive.
 *
 * The band-classifier section is the one named directly by the plan (§11):
 * `shared/ar/band-fixtures.json` is executed by both this file and
 * `test/proximity_parity_test.dart` on the Flutter side, so a change to
 * either implementation that drifts from the other fails CI on whichever
 * side runs second. Do not hand-edit expected values here without also
 * updating the fixture and re-running the Dart suite.
 */
import * as fs from "fs";
import * as path from "path";

import { classify, rawBand } from "./arCapture/domain/proximityBandCalculator";
import { issueCaptureToken, verifyCaptureToken } from "./arCapture/domain/captureToken";
import { generateSpawnPoint, pointInPolygon, type Polygon } from "./arCapture/domain/spawnPointGenerator";
import {
  CaptureHistory,
  SpawnForValidation,
  validate,
} from "./arCapture/domain/captureValidator";
import { applyCapture } from "./arCapture/domain/collectionService";
import { isQuietHours, shouldNotify } from "./arCapture/domain/notificationPolicy";
import type { BandThresholds, CaptureRequest, ProximityBand } from "./arCapture/types";

const failures: string[] = [];

function check(label: string, got: unknown, expected: unknown): void {
  const a = JSON.stringify(got);
  const b = JSON.stringify(expected);
  if (a !== b) {
    failures.push(`${label}\n      expected ${b}\n      got      ${a}`);
  }
}

// --- cross-language parity: the proximity band classifier -----------------

interface BandFixtureCase {
  label: string;
  distanceMeters: number;
  previousBand: ProximityBand;
  expectedBand: ProximityBand;
}
interface BandFixtureFile {
  thresholds: BandThresholds;
  cases: BandFixtureCase[];
}

const fixturePath = path.join(__dirname, "../../../shared/ar/band-fixtures.json");
const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8")) as BandFixtureFile;

for (const c of fixture.cases) {
  check(
    `band parity: ${c.label} (d=${c.distanceMeters}m, prev=${c.previousBand})`,
    classify(c.distanceMeters, fixture.thresholds, c.previousBand),
    c.expectedBand,
  );
}

check("rawBand ignores hysteresis entirely", rawBand(65, fixture.thresholds), "warm");

// --- SpawnPointGenerator ----------------------------------------------------

const squareZone: Polygon = [
  [
    [3.05, 36.75],
    [3.06, 36.75],
    [3.06, 36.76],
    [3.05, 36.76],
    [3.05, 36.75],
  ],
];

{
  let allInside = true;
  for (let seed = 0; seed < 500; seed++) {
    const buf = Buffer.alloc(4);
    buf.writeUInt32LE(seed, 0);
    const point = generateSpawnPoint(squareZone, buf);
    if (!pointInPolygon(point, squareZone)) {
      allInside = false;
      break;
    }
  }
  check("generateSpawnPoint always lands inside the zone (500 seeds)", allInside, true);
}

{
  const a = generateSpawnPoint(squareZone, Buffer.from("route-1‖poi-1‖2026-08-08"));
  const b = generateSpawnPoint(squareZone, Buffer.from("route-1‖poi-1‖2026-08-08"));
  check("generateSpawnPoint is deterministic for the same seed", a, b);
}

// --- CaptureValidator --------------------------------------------------------

const SPAWN: SpawnForValidation = {
  id: "spawn-1",
  state: "active",
  location: { lat: 36.7839, lng: 3.0606 },
  captureRadiusMeters: 25,
};
const NEAR_FIX = { lat: 36.78392, lng: 3.06062 }; // a couple of metres away
const FAR_FIX = { lat: 36.79, lng: 3.07 }; // roughly 1.4km away

function baseRequest(overrides: Partial<CaptureRequest> = {}): CaptureRequest {
  return {
    spawnId: SPAWN.id,
    userId: "user-1",
    captureToken: "irrelevant-here",
    fix: NEAR_FIX,
    accuracyMeters: 5,
    clientTs: new Date().toISOString(),
    clientNonce: "nonce-1",
    arTelemetry: {},
    ...overrides,
  };
}

const emptyHistory: CaptureHistory = {
  alreadyCaptured: false,
  token: { spawnId: SPAWN.id, userId: "user-1", issuedFix: NEAR_FIX, issuedAt: new Date().toISOString(), expiresAt: new Date(Date.now() + 60_000).toISOString() },
  previousAccepted: null,
  acceptedCapturesInLastHour: 0,
};

check(
  "accepted: near fix, valid token, no history",
  validate(SPAWN, baseRequest(), emptyHistory, new Date()).outcome,
  "accepted",
);

check(
  "too_far: fix outside the capture radius",
  validate(SPAWN, baseRequest({ fix: FAR_FIX }), emptyHistory, new Date()).outcome,
  "too_far",
);

check(
  "low_accuracy: accuracy worse than the 50m gate",
  validate(SPAWN, baseRequest({ accuracyMeters: 51 }), emptyHistory, new Date()).outcome,
  "low_accuracy",
);

check(
  "already_captured: an accepted row already exists for this spawn",
  validate(SPAWN, baseRequest(), { ...emptyHistory, alreadyCaptured: true }, new Date()).outcome,
  "already_captured",
);

check(
  "already_captured: spawn state is no longer active",
  validate({ ...SPAWN, state: "captured" }, baseRequest(), emptyHistory, new Date()).outcome,
  "already_captured",
);

check(
  "invalid_token: no token resolved for the presented captureToken",
  validate(SPAWN, baseRequest(), { ...emptyHistory, token: null }, new Date()).outcome,
  "invalid_token",
);

check(
  "invalid_token: token expired",
  validate(
    SPAWN,
    baseRequest(),
    { ...emptyHistory, token: { ...emptyHistory.token!, expiresAt: new Date(Date.now() - 1000).toISOString() } },
    new Date(),
  ).outcome,
  "invalid_token",
);

check(
  "stale: client timestamp far outside the clock-slack window",
  validate(
    SPAWN,
    baseRequest({ clientTs: new Date(Date.now() - 20 * 60 * 1000).toISOString() }),
    emptyHistory,
    new Date(),
  ).outcome,
  "stale",
);

check(
  "an offline replay within 24h is not stale even ~5h late",
  validate(
    SPAWN,
    baseRequest({
      clientTs: new Date(Date.now() - 5 * 60 * 60 * 1000).toISOString(),
      isOfflineReplay: true,
    }),
    emptyHistory,
    new Date(),
  ).outcome,
  "accepted",
);

check(
  "rate_limited: 20 accepted captures already this hour",
  validate(SPAWN, baseRequest(), { ...emptyHistory, acceptedCapturesInLastHour: 20 }, new Date()).outcome,
  "rate_limited",
);

{
  // Implausible speed is flagged, not blocked (plan §5.7 check 8).
  const now = new Date();
  const history: CaptureHistory = {
    ...emptyHistory,
    previousAccepted: {
      fix: { lat: 36.9, lng: 3.2 }, // ~30km away
      clientTs: new Date(now.getTime() - 60 * 1000).toISOString(), // 1 minute ago
    },
  };
  const result = validate(SPAWN, baseRequest(), history, now);
  check("implausible speed is flagged", result.flags.includes("implausible_speed"), true);
  check("implausible speed does not block acceptance", result.outcome, "accepted");
}

// --- CollectionService --------------------------------------------------------

{
  const first = applyCapture({ userId: "u1", mascotId: "m1", capturedAt: "2026-01-01T00:00:00Z" }, null, "rare");
  check("first catch is flagged as such", first.isFirstCatch, true);
  check("first catch starts the capture count at 1", first.entry.captureCount, 1);
  check("reward matches the rarity table", first.reward.points, 80);

  const second = applyCapture(
    { userId: "u1", mascotId: "m1", capturedAt: "2026-01-02T00:00:00Z" },
    first.entry,
    "rare",
  );
  check("a repeat catch is not a first catch", second.isFirstCatch, false);
  check("a repeat catch increments the count", second.entry.captureCount, 2);
  check("first-capture date is preserved on a repeat", second.entry.firstCapturedAt, first.entry.firstCapturedAt);
}

// --- NotificationPolicy --------------------------------------------------------

{
  const prefs = { quietHoursStart: 22, quietHoursEnd: 7, optedOut: false };
  check("22:00 is inside quiet hours", isQuietHours(new Date("2026-01-01T22:00:00"), prefs), true);
  check("03:00 is inside quiet hours (wraps past midnight)", isQuietHours(new Date("2026-01-01T03:00:00"), prefs), true);
  check("12:00 is outside quiet hours", isQuietHours(new Date("2026-01-01T12:00:00"), prefs), false);

  const noon = new Date("2026-01-01T12:00:00");
  check(
    "notifies when there is no recent history",
    shouldNotify({ spawnId: "s1", recent: [], now: noon, prefs }),
    true,
  );
  check(
    "suppressed during quiet hours regardless of history",
    shouldNotify({ spawnId: "s1", recent: [], now: new Date("2026-01-01T23:00:00"), prefs }),
    false,
  );
  check(
    "suppressed for an opted-out user",
    shouldNotify({ spawnId: "s1", recent: [], now: noon, prefs: { ...prefs, optedOut: true } }),
    false,
  );
  check(
    "suppressed within the 15-minute per-spawn cooldown",
    shouldNotify({
      spawnId: "s1",
      recent: [{ spawnId: "s1", sentAt: new Date(noon.getTime() - 5 * 60 * 1000).toISOString() }],
      now: noon,
      prefs,
    }),
    false,
  );
  check(
    "allowed again once the cooldown has passed",
    shouldNotify({
      spawnId: "s1",
      recent: [{ spawnId: "s1", sentAt: new Date(noon.getTime() - 16 * 60 * 1000).toISOString() }],
      now: noon,
      prefs,
    }),
    true,
  );
  check(
    "suppressed at the 6-per-day cap even for a different spawn",
    shouldNotify({
      spawnId: "s2",
      recent: Array.from({ length: 6 }, (_, i) => ({
        spawnId: `s${i}`,
        sentAt: new Date(noon.getTime() - (i + 1) * 60 * 60 * 1000).toISOString(),
      })),
      now: noon,
      prefs,
    }),
    false,
  );
}

// --- capture tokens -----------------------------------------------------------

{
  const secret = "test-secret";
  const now = new Date("2026-01-01T12:00:00Z");
  const claim = { spawnId: "spawn-1", userId: "user-1", fix: NEAR_FIX };
  const token = issueCaptureToken(claim, secret, now, 300);

  const verified = verifyCaptureToken(token.token, secret);
  check("a freshly issued token verifies", verified?.spawnId, claim.spawnId);
  check("token expiry matches the requested TTL", verified?.expiresAt, token.expiresAt);

  check("a token signed with the wrong secret fails verification", verifyCaptureToken(token.token, "wrong-secret"), null);
  check("a tampered payload fails verification", verifyCaptureToken(token.token + "x", secret), null);
  check("garbage input fails verification rather than throwing", verifyCaptureToken("not-a-token", secret), null);
}

if (failures.length > 0) {
  console.log(`FAILED (${failures.length}):`);
  for (const f of failures) console.log(`  - ${f}`);
  process.exit(1);
}
console.log("all AR capture domain checks passed");
