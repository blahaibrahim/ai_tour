/**
 * Placeholder data, so the Flutter client (or a manual `curl`) can be
 * developed against the real HTTP contract before the module behind it
 * exists — same purpose as `routeGeneration/fixtures.ts`, and deliberately
 * keyed to the same fixture city and POI ids so a request built from one
 * module's fixtures lines up with the other's.
 *
 * The mascot is the fennec the client already ships (`assets/3d/fennec.glb`)
 * and the spawn sits on the fixture route's Ketchaoua Mosque stop
 * (`e0000000-0000-4000-8000-00000000000a`, see `routeGeneration/fixtures.ts`).
 *
 * Delete this file when the orchestrator is implemented.
 */
import { FIXTURE_STOPS } from "../routeGeneration/fixtures";
import type { ArContent, Mascot, MascotSpawn, SpawnManifest } from "./types";

export const FIXTURE_MASCOT_ID = "b1000000-0000-4000-8000-000000000001";
export const FIXTURE_AR_CONTENT_ID = "b2000000-0000-4000-8000-000000000001";
export const FIXTURE_SPAWN_ID = "b3000000-0000-4000-8000-000000000001";

const MOSQUE = FIXTURE_STOPS[0]; // Ketchaoua Mosque — see routeGeneration/fixtures.ts

export const FIXTURE_MASCOT: Mascot = {
  id: FIXTURE_MASCOT_ID,
  key: "fennec",
  nameFr: "Fennec",
  nameAr: "فنك",
  nameEn: "Fennec",
  loreFr: "Le fennec, petit renard du Sahara aux grandes oreilles.",
  loreAr: "الفنك، ثعلب صغير من الصحراء الكبرى بأذنين كبيرتين.",
  loreEn: "The fennec, a small Saharan fox known for its oversized ears.",
  rarity: "common",
  modelGlbRef: "mascots/fennec.glb",
  modelUsdzRef: "mascots/fennec.usdz",
  modelChecksum: "0".repeat(64), // placeholder — real checksum computed at asset upload
  scaleMeters: 0.6,
  thumbnailRef: null,
};

/** A small square around the mosque, standing in for a curated,
 * safety-reviewed isochrone-minus-obstacles polygon (plan §5.1). Real spawn
 * zones are never this — see `ArContentRepository.upsertSpawnZone`'s note. */
function squareZone(centre: { lat: number; lng: number }, halfSideMeters: number): ArContent["spawnZone"] {
  const metresPerDegreeLat = 111_320;
  const dLat = halfSideMeters / metresPerDegreeLat;
  const dLng = halfSideMeters / (metresPerDegreeLat * Math.cos((centre.lat * Math.PI) / 180));
  const { lat, lng } = centre;
  return [
    [
      [lng - dLng, lat - dLat],
      [lng + dLng, lat - dLat],
      [lng + dLng, lat + dLat],
      [lng - dLng, lat + dLat],
      [lng - dLng, lat - dLat], // ring closes
    ],
  ];
}

export const FIXTURE_AR_CONTENT: ArContent = {
  id: FIXTURE_AR_CONTENT_ID,
  poiId: MOSQUE.poiId,
  mascotId: FIXTURE_MASCOT_ID,
  spawnZone: squareZone(MOSQUE.location, 40),
  spawnRadiusMeters: 60,
  captureRadiusMeters: 25,
  hotRadiusMeters: 60,
  bandThresholds: {},
  presentationDistanceMeters: 4.0,
  isEnabled: true,
  zoneReviewedBy: "fixture",
};

export function fixtureSpawn(routeId: string): MascotSpawn {
  return {
    id: FIXTURE_SPAWN_ID,
    routeId,
    poiId: MOSQUE.poiId,
    arContentId: FIXTURE_AR_CONTENT_ID,
    mascotId: FIXTURE_MASCOT_ID,
    // A few metres off the POI's own coordinate — inside the fixture zone,
    // and close enough that a tester standing at the mosque is in BURNING.
    location: { lat: MOSQUE.location.lat + 0.00008, lng: MOSQUE.location.lng + 0.00005 },
    spawnSeed: "fixture",
    spawnEpoch: new Date().toISOString().slice(0, 10),
    state: "active",
    expiresAt: null,
    createdAt: new Date().toISOString(),
  };
}

export function fixtureManifest(routeId: string): SpawnManifest {
  const spawn = fixtureSpawn(routeId);
  return {
    routeId,
    spawns: [
      {
        spawnId: spawn.id,
        poiId: spawn.poiId,
        location: spawn.location,
        captureRadiusMeters: FIXTURE_AR_CONTENT.captureRadiusMeters,
        hotRadiusMeters: FIXTURE_AR_CONTENT.hotRadiusMeters,
        bandThresholds: {
          coldMeters: 300,
          warmMeters: 150,
          hotMeters: FIXTURE_AR_CONTENT.hotRadiusMeters,
          burningMeters: FIXTURE_AR_CONTENT.captureRadiusMeters,
        },
        presentationDistanceMeters: FIXTURE_AR_CONTENT.presentationDistanceMeters,
        mascot: {
          id: FIXTURE_MASCOT.id,
          key: FIXTURE_MASCOT.key,
          name: FIXTURE_MASCOT.nameEn,
          rarity: FIXTURE_MASCOT.rarity,
          modelGlbUrl: "https://example.invalid/fixtures/fennec.glb",
          modelUsdzUrl: "https://example.invalid/fixtures/fennec.usdz",
          modelChecksum: FIXTURE_MASCOT.modelChecksum,
          scaleMeters: FIXTURE_MASCOT.scaleMeters,
        },
      },
    ],
  };
}
