/**
 * Checks for the route generation module — the pure domain layer, plus a live
 * end-to-end generation against Supabase when credentials are present.
 *
 *     npm test
 *
 * Same zero-dependency style as `testArCapture.ts` and `testPoiRules.ts`: a
 * `check(label, got, expected)` harness collecting failures, exit 1 if any
 * survive.
 *
 * The domain half runs anywhere — it is pure functions over fixed inputs,
 * which is what spec §11 asks for ("the optimizer's ordering step against a
 * fixed known matrix, the assembler, the estimator arithmetic"). The
 * end-to-end half is skipped, loudly, without SUPABASE_URL, so this stays
 * runnable on a machine with no project attached.
 *
 * Nothing here calls a routing provider. The straight-line adapter stands in,
 * so no test run ever spends free-tier quota — spec §11 again. That is forced
 * below rather than left to whether a key happens to be configured: a machine
 * with GRAPHHOPPER_API_KEY set must not pay a different price for `npm test`
 * than one without, and on the free plan a full run would exhaust the
 * per-minute limit and then fail on timings rather than on logic.
 */
process.env.ROUTING_PROVIDER_FORCE_ESTIMATE = "1";

import { Config } from "./config";
import {
  type CacheAdapter,
  InMemoryCacheAdapter,
  RedisCacheAdapter,
  ResilientCacheAdapter,
  legKey,
} from "./routeGeneration/adapters/cacheAdapter";
import { StraightLineRoutingProvider } from "./routeGeneration/adapters/routingProviderAdapter";
import { cluster, distanceMeters } from "./routeGeneration/domain/clusteringEngine";
import { fitToBudget, stopsToDrop, valuePerMinute } from "./routeGeneration/domain/budgetFitter";
import { buildSegments } from "./routeGeneration/domain/responseAssembler";
import {
  nearestNeighbourOrder,
  orderStopsWithinCluster,
  twoOptPass,
} from "./routeGeneration/domain/routeOptimizer";
import { computeDayCountFlag, estimate, pointInPolygon } from "./routeGeneration/domain/timeEstimator";
import { isOpenAt } from "./routeGeneration/data/poiRepository";
import type { Cluster, DurationMatrix, Poi } from "./routeGeneration/types";

const failures: string[] = [];

function check(label: string, got: unknown, expected: unknown): void {
  const a = JSON.stringify(got);
  const b = JSON.stringify(expected);
  if (a !== b) failures.push(`${label}\n      expected ${b}\n      got      ${a}`);
}

function poi(id: string, lat: number, lng: number, dwell = 20, score: number | null = 50): Poi {
  return {
    id,
    cityId: "city",
    categoryId: "cat",
    categoryKey: "museum",
    nameEn: id,
    nameFr: null,
    nameAr: null,
    descriptionEn: null,
    descriptionFr: null,
    descriptionAr: null,
    location: { lat, lng },
    openingHoursRaw: null,
    avgVisitDurationMinutes: dwell,
    checkpointRadiusMeters: 30,
    arContentId: null,
    stampId: null,
    externalRef: null,
    source: "team_seeded",
    status: "published",
    photoUrl: null,
    photoAttribution: null,
    photoLicense: null,
    photoSourceUrl: null,
    interestScore: score,
  };
}

// Wrapped rather than run at top level: this package compiles to CommonJS, so
// top-level await is not available here.
async function main(): Promise<void> {
// --- clustering ------------------------------------------------------------
{
  // Three POIs ~100 m apart, plus one 5 km away.
  const near = [poi("a", 36.7853, 3.0588), poi("b", 36.7860, 3.0592), poi("c", 36.7848, 3.0580)];
  const far = poi("far", 36.8300, 3.0588);

  const clusters = cluster([...near, far], 500);
  check("a distant POI gets its own cluster", clusters.length, 2);
  check(
    "the three near POIs land together",
    clusters.find((c) => c.pois.length === 3)?.pois.length,
    3,
  );

  // The chaining trap: POIs 400 m apart in a line. Seed-based grouping must
  // not swallow the whole line into one "walkable" cluster.
  const line = [0, 1, 2, 3, 4].map((i) => poi(`l${i}`, 36.78 + i * 0.0036, 3.05));
  const chained = cluster(line, 500);
  const widest = Math.max(
    ...chained.map((c) =>
      Math.max(
        ...c.pois.flatMap((p) => c.pois.map((q) => distanceMeters(p.location, q.location))),
      ),
    ),
  );
  check("no cluster exceeds twice the radius in diameter", widest <= 1000, true);

  // The anchor must be a real POI, never a bare centroid in the sea.
  const anchored = cluster(near, 500)[0]!;
  check(
    "the anchor is one of the cluster's own POIs",
    near.some(
      (p) => p.location.lat === anchored.anchor.lat && p.location.lng === anchored.anchor.lng,
    ),
    true,
  );

  check("an empty POI list yields no clusters", cluster([], 500).length, 0);
}

// --- route optimizer -------------------------------------------------------
{
  // Four points on a line: 0 - 1 - 2 - 3. Visiting them in order is optimal;
  // a deliberately bad start order must be repaired.
  const points = [
    { lat: 0, lng: 0 },
    { lat: 0, lng: 1 },
    { lat: 0, lng: 2 },
    { lat: 0, lng: 3 },
  ];
  const seconds = (i: number, j: number): number => Math.abs(i - j) * 60;
  const matrix: DurationMatrix = {
    points,
    durations: points.map((_, i) => points.map((_, j) => seconds(i, j))),
  };

  check(
    "nearest neighbour walks the line in order",
    nearestNeighbourOrder(matrix, [0, 1, 2, 3], 0),
    [0, 1, 2, 3],
  );

  const cost = (order: number[]): number =>
    order.slice(1).reduce((sum, v, i) => sum + seconds(order[i]!, v), 0);
  const repaired = twoOptPass(matrix, [0, 2, 1, 3]);
  check("2-opt does not make a crossed tour worse", cost(repaired) <= cost([0, 2, 1, 3]), true);

  // The open-path rule: the tour must not be scored as if it returned to the
  // start, which is what makes an optimizer double back for no reason.
  check("2-opt keeps an already-optimal open path", twoOptPass(matrix, [0, 1, 2, 3]), [0, 1, 2, 3]);

  // Indexing by coordinate, not array position — the failure the reference
  // implementation ships. The matrix here is in a DIFFERENT order from the
  // cluster's POI list, so position-based lookup would silently misorder.
  const shuffledPoints = [points[3]!, points[0]!, points[2]!, points[1]!];
  const shuffled: DurationMatrix = {
    points: shuffledPoints,
    durations: shuffledPoints.map((a) =>
      shuffledPoints.map((b) => Math.abs(a.lng - b.lng) * 60),
    ),
  };
  const c: Cluster = {
    id: 0,
    pois: [poi("p0", 0, 0), poi("p2", 0, 2), poi("p1", 0, 1), poi("p3", 0, 3)],
    anchor: { lat: 0, lng: 0 },
  };
  check(
    "stops are ordered against a matrix whose rows are in a different order",
    orderStopsWithinCluster(c, shuffled).map((p) => p.id),
    ["p0", "p1", "p2", "p3"],
  );
}

// --- time estimator --------------------------------------------------------
{
  const stops = [poi("a", 0, 0, 30), poi("b", 0, 1, 30), poi("c", 0, 2, 30)];
  const points = stops.map((s) => s.location);
  const matrix: DurationMatrix = {
    points,
    // 10 minutes between adjacent stops.
    durations: points.map((_, i) => points.map((_, j) => Math.abs(i - j) * 600)),
  };

  const result = await estimate({
    orderedStops: stops,
    matrix,
    dwellTimes: {},
    timeBudgetMinutes: 480,
  });
  // 3 × 30 dwell + 2 × 10 travel.
  check("total is travel plus dwell", result.totalMinutes, 110);
  check("a route inside the budget is one day", result.dayCountFlag, 1);

  // 110 minutes of route against an 80-minute day: stops a and b fit (30 + 10
  // + 30 = 70), c does not, so it starts a second day.
  check("a route past the budget needs more days", await computeDayCountFlag(stops, matrix, 80), 2);

  // The day count is sequential packing, not `ceil(total / budget)` — and the
  // difference is visible here. 110 minutes against a 60-minute day looks like
  // two days by division, but a second stop costs 10 travel + 30 dwell on top
  // of the first stop's 30, which is 70 and does not fit. Each stop gets its
  // own day. Division would have promised the traveller a schedule that does
  // not exist.
  check("packing beats division when travel does not divide evenly",
    await computeDayCountFlag(stops, matrix, 60), 3);

  // The geographic half: arithmetic says one day, but a stop outside the
  // reachable area makes it two regardless.
  const tinyBox: Array<Array<[number, number]>> = [
    [
      [-0.5, -0.5],
      [0.5, -0.5],
      [0.5, 0.5],
      [-0.5, 0.5],
      [-0.5, -0.5],
    ],
  ];
  check(
    "an unreachable stop raises the day count even when the arithmetic fits",
    await computeDayCountFlag(stops, matrix, 480, {}, {
      coordinates: tinyBox,
      timeBudgetMinutes: 480,
      mode: "driving",
    }),
    2,
  );

  check("point inside the ring", pointInPolygon({ lat: 0, lng: 0 }, tinyBox), true);
  check("point outside the ring", pointInPolygon({ lat: 0, lng: 2 }, tinyBox), false);
  check(
    "an unusable ring does not accuse a stop of being unreachable",
    pointInPolygon({ lat: 0, lng: 2 }, []),
    true,
  );

  check("no stops is zero minutes and one day", await estimate({
    orderedStops: [],
    matrix,
    dwellTimes: {},
    timeBudgetMinutes: 60,
  }), { totalMinutes: 0, dayCountFlag: 1 });
}

// --- response assembler ----------------------------------------------------
{
  const clusters: Cluster[] = [
    {
      id: 0,
      pois: [poi("a", 0, 0), poi("b", 0, 0.01)],
      anchor: { lat: 0, lng: 0 },
    },
    {
      id: 1,
      pois: [poi("c", 1, 1)],
      anchor: { lat: 1, lng: 1 },
    },
  ];

  const segments = buildSegments(
    clusters,
    [{ durationSeconds: 600, distanceMeters: 5000, geometry: [] }],
    [{ durationSeconds: 300, distanceMeters: 400, geometry: [] }],
  );

  check("two clusters with one walk hop give two segments", segments.length, 2);
  check("the walk hop is tagged walk and carries its cluster", segments[0]!.mode, "walk");
  check("an intra-cluster leg carries its cluster id", segments[0]!.clusterId, 0);
  check("the drive hop is tagged drive", segments[1]!.mode, "drive");
  // A drive runs anchor to anchor, so it has no POI endpoints — a client that
  // infers mode from cluster ids gets this wrong.
  check("a drive leg has no POI endpoints", [segments[1]!.fromPoiId, segments[1]!.toPoiId], [null, null]);
  check("seconds become minutes on the way out", segments[1]!.durationMinutes, 10);
  check(
    "a leg with no geometry degrades to a straight line rather than an empty one",
    segments[1]!.geometry.length,
    2,
  );

  // Missing legs entirely (provider down for every call) must still produce a
  // complete, drawable route.
  const degraded = buildSegments(clusters, [], []);
  check("segments survive a provider that returned nothing", degraded.length, 2);
}

// --- opening hours ---------------------------------------------------------
{
  const tuesday10am = new Date("2026-08-11T10:00:00");
  const sunday10am = new Date("2026-08-16T10:00:00");
  const tuesday3am = new Date("2026-08-11T03:00:00");

  check("no recorded hours is not evidence of being shut", isOpenAt(null, tuesday10am), true);
  check("24/7 is always open", isOpenAt("24/7", tuesday3am), true);
  check("inside the window", isOpenAt("Mo-Su 08:00-18:00", tuesday10am), true);
  check("outside the window", isOpenAt("Mo-Su 08:00-18:00", tuesday3am), false);
  check("a day outside the range", isOpenAt("Tu-Sa 09:00-17:00", sunday10am), false);
  check("a day inside the range", isOpenAt("Tu-Sa 09:00-17:00", tuesday10am), true);
  // Fails open: unparseable syntax must not silently empty a route.
  check("unparseable hours fail open", isOpenAt("sunrise-sunset; PH off", tuesday3am), true);
}

// --- straight-line provider ------------------------------------------------
{
  const provider = new StraightLineRoutingProvider("graphhopper");
  const a = { lat: 36.7853, lng: 3.0588 };
  const b = { lat: 36.7605, lng: 3.083 };

  const walk = await provider.getRoute([a, b], "walking");
  const drive = await provider.getRoute([a, b], "driving");
  check("driving beats walking over the same distance", drive.durationSeconds < walk.durationSeconds, true);
  check("a leg reports a non-zero distance", drive.distanceMeters > 0, true);
  check("a single-point route is zero length", (await provider.getRoute([a], "walking")).distanceMeters, 0);

  const matrix = await provider.getMatrix([a, b], "driving");
  check("the matrix diagonal is zero", matrix.durations[0]![0], 0);
  check("the matrix is symmetric", matrix.durations[0]![1], matrix.durations[1]![0]);

  const iso = await provider.getIsochrone(a, 30, "driving");
  check("the isochrone contains its own origin", pointInPolygon(a, iso.coordinates), true);
}

// --- budget fitter ---------------------------------------------------------
{
  // Same dwell, different worth: the better one must survive.
  const cheapGood = poi("cheap-good", 0, 0, 20, 80);
  const cheapBad = poi("cheap-bad", 0, 0.01, 20, 20);
  check(
    "value is measured per minute, not per stop",
    valuePerMinute(cheapGood) > valuePerMinute(cheapBad),
    true,
  );

  // A great museum that eats the whole day loses to two good monuments.
  const longGreat = poi("long-great", 0, 0, 100, 90);
  const shortGood = poi("short-good", 0, 0, 20, 60);
  check(
    "a long visit must earn its minutes",
    valuePerMinute(shortGood) > valuePerMinute(longGreat),
    true,
  );

  // An unscored POI is mid-ranked, not worthless — otherwise every curated row
  // is dropped before every ingested one.
  const unscored = poi("unscored", 0, 0, 20, null);
  check("an unscored POI outranks a bad one", valuePerMinute(unscored) > valuePerMinute(cheapBad), true);
  check("an unscored POI ranks below a good one", valuePerMinute(unscored) < valuePerMinute(cheapGood), true);

  const many = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => poi(`p${i}`, 0, i * 0.01, 30, 50 + i));
  const fitted = fitToBudget({
    pois: many,
    timeBudgetMinutes: 120,
    travelAllowancePerStopMinutes: 10,
    minimumStops: 1,
  });
  // 30 dwell + 10 travel = 40 a stop, so three fit in 120.
  check("the fit respects the budget", fitted.length, 3);
  check(
    "the fit keeps the best-value stops",
    fitted.map((p) => p.id).sort(),
    ["p5", "p6", "p7"],
  );

  check(
    "a budget too small for anything still returns the minimum",
    fitToBudget({ pois: many, timeBudgetMinutes: 5, travelAllowancePerStopMinutes: 10, minimumStops: 1 }).length,
    1,
  );
  check(
    "an empty catalogue fits to nothing",
    fitToBudget({ pois: [], timeBudgetMinutes: 480, travelAllowancePerStopMinutes: 10, minimumStops: 1 }).length,
    0,
  );

  // Determinism: the same request twice must not reorder equal-value stops.
  const tied = [poi("b", 0, 0, 30, 50), poi("a", 0, 0.01, 30, 50), poi("c", 0, 0.02, 30, 50)];
  check(
    "equal value breaks ties deterministically",
    fitToBudget({ pois: tied, timeBudgetMinutes: 80, travelAllowancePerStopMinutes: 10, minimumStops: 1 })
      .map((p) => p.id),
    fitToBudget({ pois: [...tied].reverse(), timeBudgetMinutes: 80, travelAllowancePerStopMinutes: 10, minimumStops: 1 })
      .map((p) => p.id),
  );

  // The trim sheds travel as well as dwell. Counting dwell alone over-dropped,
  // which made a bigger budget return a shorter route.
  const ordered = [0, 1, 2, 3].map((i) => poi(`o${i}`, 0, i * 0.01, 30, 40 + i * 10));
  const shed = stopsToDrop(ordered, 40, 1, 10);
  check("an overshoot of one stop's cost drops one stop", shed.size, 1);
  check("the worst stop is the one dropped", [...shed], ["o0"]);

  check("nothing is dropped when the route already fits", stopsToDrop(ordered, 0, 1, 10).size, 0);
  check(
    "the minimum is never breached",
    stopsToDrop(ordered, 10_000, 2, 10).size,
    2,
  );
}

// --- cache -----------------------------------------------------------------
// "Assert a cache hit skips the adapter call entirely (mock call-count)" is one
// of spec §11's named cases, and the leg cache is where it matters most: legs
// are one provider call per hop, against a matrix's one per request.
{
  const cache = new InMemoryCacheAdapter();
  const a = { lat: 36.7853, lng: 3.0588 };
  const b = { lat: 36.7862, lng: 3.0607 };

  check("a cold leg is a miss", await cache.getLeg(a, b, "walking"), null);

  const leg = { durationSeconds: 300, distanceMeters: 400, geometry: [a, b] };
  await cache.setLeg(a, b, "walking", leg);

  check("a stored leg comes back", (await cache.getLeg(a, b, "walking"))?.distanceMeters, 400);
  check("hits and misses are counted", [cache.stats.legHits, cache.stats.legMisses], [1, 1]);

  // Direction is part of the key: A→B and B→A are different journeys on a
  // one-way street, and sharing an entry would draw the path backwards.
  check("the reverse leg is a separate entry", await cache.getLeg(b, a, "walking"), null);
  // So is the profile — the walking route between two points is not the
  // driving one.
  check("the other profile is a separate entry", await cache.getLeg(a, b, "driving"), null);

  // The key carries no city, theme or route id, which is the whole point: the
  // same hop in a different route must hit.
  check(
    "the key is the endpoints and profile alone",
    legKey(a, b, "walking"),
    "walking:36.7853000,3.0588000>36.7862000,3.0607000",
  );

  cache.clear();
  check("clearing empties the leg cache", await cache.getLeg(a, b, "walking"), null);
}

// --- Redis adapter ---------------------------------------------------------
// Against a fake client rather than a server: the adapter's job is key naming,
// serialization and TTL, and none of those need a running Redis to check.
{
  const store = new Map<string, { value: string; ttl: number }>();
  const fake = {
    get: async (key: string) => store.get(key)?.value ?? null,
    set: async (key: string, value: string, _mode: "EX", seconds: number) => {
      store.set(key, { value, ttl: seconds });
      return "OK";
    },
  };
  const redis = new RedisCacheAdapter(fake);
  const a = { lat: 36.7853, lng: 3.0588 };
  const b = { lat: 36.7862, lng: 3.0607 };

  check("a cold Redis read is a miss", await redis.getLeg(a, b, "walking"), null);

  await redis.setLeg(a, b, "walking", {
    durationSeconds: 300,
    distanceMeters: 400,
    geometry: [a, b],
  });
  const back = await redis.getLeg(a, b, "walking");
  check("a leg round-trips through JSON intact", back?.geometry, [a, b]);

  // Prefixed, because Redis is routinely shared across services and
  // environments — an unprefixed `matrix:...` would collide with anything
  // else using the same instance.
  check(
    "keys are namespaced",
    [...store.keys()].every((k) => k.startsWith("route-gen:")),
    true,
  );
  check("legs get the 7-day TTL in seconds", store.get([...store.keys()][0]!)?.ttl, 7 * 24 * 3600);

  await redis.setMatrix("city-1", "walking:abc", { durations: [[0]], points: [a] });
  check(
    "a matrix key carries the city and the point fingerprint",
    store.has("route-gen:matrix:city-1:walking:abc"),
    true,
  );

  // A value written by an older shape of this code must read as a miss, not
  // throw — a format change should cost a cold cache, not an outage.
  store.set("route-gen:leg:walking:0.0000000,0.0000000>1.0000000,1.0000000", {
    value: "{not json",
    ttl: 60,
  });
  check(
    "an unparseable entry reads as a miss",
    await redis.getLeg({ lat: 0, lng: 0 }, { lat: 1, lng: 1 }, "walking"),
    null,
  );
}

// --- cache resilience ------------------------------------------------------
// The failure mode that matters: Redis going away mid-process must cost
// latency and quota, never the request. The reference implementation commits
// to its backend at boot, so a later outage surfaces as a 500.
{
  const exploding: CacheAdapter = {
    getMatrix: async () => { throw new Error("ECONNREFUSED"); },
    setMatrix: async () => { throw new Error("ECONNREFUSED"); },
    getIsochrone: async () => { throw new Error("ECONNREFUSED"); },
    setIsochrone: async () => { throw new Error("ECONNREFUSED"); },
    getLeg: async () => { throw new Error("ECONNREFUSED"); },
    setLeg: async () => { throw new Error("ECONNREFUSED"); },
  };
  const resilient = new ResilientCacheAdapter(exploding);
  const a = { lat: 1, lng: 1 };
  const b = { lat: 2, lng: 2 };
  const leg = { durationSeconds: 60, distanceMeters: 100, geometry: [a, b] };

  // Neither of these may throw.
  await resilient.setLeg(a, b, "walking", leg);
  check(
    "a write survives a dead Redis and still lands in memory",
    (await resilient.getLeg(a, b, "walking"))?.distanceMeters,
    100,
  );

  await resilient.setMatrix("c", "m", { durations: [[0]], points: [a] });
  check(
    "matrices survive a dead Redis too",
    (await resilient.getMatrix("c", "m"))?.points.length,
    1,
  );
  check("a miss on a dead Redis is a miss, not a throw", await resilient.getMatrix("c", "other"), null);
}

// --- end-to-end against the real database ----------------------------------

if (!Config.SUPABASE_URL || !Config.SUPABASE_ANON_KEY) {
  console.log("SKIPPED end-to-end checks: SUPABASE_URL / SUPABASE_ANON_KEY not set");
} else {
  const routeGeneration = await import("./routeGeneration");

  const cities = await routeGeneration.listCities();
  check("the catalogue has cities", cities.length > 0, true);

  const city = cities.find((c) => c.rolloutStatus !== "planning");
  if (!city) {
    failures.push("no routable city in the catalogue — did the seed migration run?");
  } else {
    check("a seeded city has a map centre", city.centre !== null, true);

    const themes = await routeGeneration.listThemes(city.id);
    check(`${city.name} offers at least one theme`, themes.length > 0, true);

    // Every offered theme must actually be answerable. This is the 422 class
    // of bug: a theme in the picker that no POI can satisfy.
    for (const theme of themes) {
      const route = await routeGeneration.generateRoute({
        cityId: city.id,
        theme: theme.key,
        timeBudgetMinutes: 480,
        transportMode: "hybrid",
        locale: "en",
        userId: null,
        sessionId: null,
      });

      check(`${theme.key}: the route has stops`, route.stops.length > 0, true);
      check(`${theme.key}: the route was persisted with an id`, route.id.length > 0, true);
      check(
        `${theme.key}: stop sequence is dense and ordered`,
        route.stops.map((s) => s.sequenceOrder),
        route.stops.map((_, i) => i),
      );
      check(
        `${theme.key}: every segment carries a mode tag`,
        route.segments.every((s) => s.mode === "walk" || s.mode === "drive"),
        true,
      );
      check(
        `${theme.key}: every segment has drawable geometry`,
        route.segments.every((s) => s.geometry.length >= 2),
        true,
      );
      check(`${theme.key}: the day count is at least 1`, route.dayCountFlag >= 1, true);
      check(
        `${theme.key}: every stop carries a checkpoint radius`,
        route.stops.every((s) => s.checkpointRadiusMeters > 0),
        true,
      );

      // Reading it back must give the same route.
      const readBack = await routeGeneration.getRoute(route.id, null);
      check(`${theme.key}: read-back has the same stop count`, readBack.stops.length, route.stops.length);
      check(`${theme.key}: read-back preserves the segments`, readBack.segments.length, route.segments.length);
    }
  }
}
}

main().then(
  () => {
    if (failures.length > 0) {
      console.log(`FAILED (${failures.length}):`);
      for (const f of failures) console.log(`  - ${f}`);
      process.exit(1);
    }
    console.log("all route generation checks passed");
    // The Supabase client keeps a socket warm; nothing is pending, so leaving
    // the process to drain would just hang the test run.
    process.exit(0);
  },
  (error) => {
    console.error("route generation checks threw:", error);
    process.exit(1);
  },
);
