/**
 * Placeholder data, so the Flutter app is buildable against the new contract
 * before the module behind it exists.
 *
 * This is not seed data and not test data — it is the stand-in the endpoints
 * serve while `ROUTE_GENERATION_MODE=fixture`. Everything is shaped exactly
 * like the real response, including the parts that are easy to get wrong:
 * two clusters rather than one, a drive leg between them, walk legs inside
 * them, per-POI checkpoint radii, and a `dayCountFlag` that is sometimes 2.
 *
 * The coordinates are real places in Algiers, so the map, the ordering and the
 * drive/walk split all look right while the UI is being built. The durations
 * are plausible, not measured.
 *
 * Every id here must be a syntactically valid UUID. The controller validates
 * `:routeId`, `:progressId` and `poi_id` against a hex UUID pattern before it
 * ever reaches this module, so a mnemonic prefix like `r…`/`p…`/`g…` — which
 * is not hex — makes the server reject its own fixtures with a 400. That
 * silently broke every path keyed on an id (refine, get-route, start-progress,
 * checkpoint) while plain generation kept working, which is the most confusing
 * shape the bug could take. Prefixes are kept for readability but drawn from
 * `a`-`f` only.
 *
 * Delete this file when the orchestrator is implemented.
 */
import {
  Category,
  CityConfig,
  RouteRequest,
  RouteResponse,
  RouteStop,
  Segment,
} from "./types";

export const FIXTURE_CITY_ID = "11111111-1111-4111-8111-111111111111";

export const FIXTURE_CITIES: CityConfig[] = [
  {
    id: FIXTURE_CITY_ID,
    regionId: null,
    name: "Algiers",
    nameFr: "Alger",
    nameAr: "الجزائر",
    centre: { lat: 36.7538, lng: 3.0588 },
    clusterRadiusMeters: 500,
    activeRoutingProvider: "graphhopper",
    rolloutStatus: "pilot",
    featureFlags: {},
  },
  {
    id: "22222222-2222-4222-8222-222222222222",
    regionId: null,
    name: "Constantine",
    nameFr: "Constantine",
    nameAr: "قسنطينة",
    centre: { lat: 36.365, lng: 6.6147 },
    clusterRadiusMeters: 500,
    activeRoutingProvider: "graphhopper",
    // Deliberately not routable: the city picker must show it and the
    // generate call must refuse it, which is the phased-rollout behaviour.
    rolloutStatus: "planning",
    featureFlags: {},
  },
];

export const FIXTURE_CATEGORIES: Category[] = [
  {
    id: "c1000000-0000-4000-8000-000000000001",
    key: "heritage",
    labelEn: "Heritage",
    labelFr: "Patrimoine",
    labelAr: "تراث",
    iconRef: "landmark",
    colorHex: "#8B6F47",
  },
  {
    id: "c1000000-0000-4000-8000-000000000002",
    key: "religious",
    labelEn: "Religious sites",
    labelFr: "Sites religieux",
    labelAr: "مواقع دينية",
    iconRef: "mosque",
    colorHex: "#2E7D6F",
  },
  {
    id: "c1000000-0000-4000-8000-000000000003",
    key: "museum",
    labelEn: "Museums",
    labelFr: "Musées",
    labelAr: "متاحف",
    iconRef: "museum",
    colorHex: "#4A6FA5",
  },
  {
    id: "c1000000-0000-4000-8000-000000000004",
    key: "viewpoint",
    labelEn: "Viewpoints",
    labelFr: "Points de vue",
    labelAr: "مناظر",
    iconRef: "binoculars",
    colorHex: "#B5651D",
  },
  {
    id: "c1000000-0000-4000-8000-000000000005",
    key: "market",
    labelEn: "Markets",
    labelFr: "Marchés",
    labelAr: "أسواق",
    iconRef: "basket",
    colorHex: "#A03E52",
  },
];

/** Themes the picker offers. NOT IN SPEC as a table — see `poiSelector.ts`'s
 * note about the theme-to-category mapping having no home in the schema. */
export const FIXTURE_THEMES = [
  { key: "history", labelEn: "History", labelFr: "Histoire", labelAr: "تاريخ" },
  { key: "culture", labelEn: "Culture", labelFr: "Culture", labelAr: "ثقافة" },
  { key: "nature", labelEn: "Nature", labelFr: "Nature", labelAr: "طبيعة" },
  { key: "food", labelEn: "Food", labelFr: "Gastronomie", labelAr: "مأكولات" },
];

function stop(
  order: number,
  clusterId: number,
  poiId: string,
  name: string,
  categoryKey: string,
  lat: number,
  lng: number,
  dwellMinutes: number,
  description: string,
): RouteStop {
  return {
    poiId,
    sequenceOrder: order,
    clusterId,
    name,
    description,
    categoryKey,
    location: { lat, lng },
    dwellMinutes,
    // Per-POI, not global: a tight alley needs a smaller radius than an open
    // esplanade, and GPS drift in the Casbah makes one global value wrong in
    // both directions.
    checkpointRadiusMeters: clusterId === 0 ? 25 : 60,
    openingHoursRaw: "Tu-Su 09:00-17:00",
    photoUrl: null,
    photoAttribution: null,
    photoLicense: null,
    photoSourceUrl: null,
    arContentId: null,
    stampId: null,
  };
}

/** Two clusters: the Casbah on foot, then a drive up to the Riadh El Feth
 * plateau and another walking loop. Exactly the shape the hybrid transport
 * model exists to produce. */
// Exported so arCapture/fixtures.ts can key its own fixture spawn to a real
// fixture POI id — see that file's module docstring.
export const FIXTURE_STOPS: RouteStop[] = [
  stop(0, 0, "e0000000-0000-4000-8000-00000000000a", "Ketchaoua Mosque", "religious",
    36.7839, 3.0606, 25,
    "Ottoman mosque at the foot of the Casbah, rebuilt in the 1840s and returned to worship in 1962."),
  stop(1, 0, "e0000000-0000-4000-8000-00000000000b", "Dar Aziza", "heritage",
    36.7845, 3.0602, 20,
    "A 16th-century Ottoman palace on the Place des Martyrs, one of the last of the Djenina complex."),
  stop(2, 0, "e0000000-0000-4000-8000-00000000000c", "Bastion 23", "heritage",
    36.7869, 3.0555, 30,
    "Three Ottoman houses and a fort on the seafront, the last surviving fragment of the lower Casbah."),
  stop(3, 1, "e0000000-0000-4000-8000-00000000000d", "Maqam Echahid", "heritage",
    36.7457, 3.0697, 30,
    "Three concrete palm fronds rising over the bay, Algiers' memorial to independence."),
  stop(4, 1, "e0000000-0000-4000-8000-00000000000e", "Musée national du Moudjahid", "museum",
    36.7452, 3.0699, 40,
    "The war of independence told through documents, photographs and personal effects."),
  stop(5, 1, "e0000000-0000-4000-8000-00000000000f", "Riadh El Feth Esplanade", "viewpoint",
    36.7443, 3.0705, 15,
    "The terrace below the memorial, looking north across the whole bay."),
];

function walkLeg(from: RouteStop, to: RouteStop, minutes: number, metres: number): Segment {
  return {
    mode: "walk",
    fromPoiId: from.poiId,
    toPoiId: to.poiId,
    clusterId: from.clusterId,
    durationMinutes: minutes,
    distanceMeters: metres,
    geometry: [from.location, to.location],
  };
}

const FIXTURE_SEGMENTS: Segment[] = [
  walkLeg(FIXTURE_STOPS[0], FIXTURE_STOPS[1], 2, 80),
  walkLeg(FIXTURE_STOPS[1], FIXTURE_STOPS[2], 8, 520),
  {
    // The one inter-cluster leg. `clusterId: null` marks it as belonging to no
    // cluster, which is how the client tells "drive here" from "walk this loop".
    mode: "drive",
    fromPoiId: FIXTURE_STOPS[2].poiId,
    toPoiId: FIXTURE_STOPS[3].poiId,
    clusterId: null,
    durationMinutes: 14,
    distanceMeters: 5_400,
    geometry: [
      FIXTURE_STOPS[2].location,
      { lat: 36.7772, lng: 3.0598 },
      { lat: 36.7654, lng: 3.0641 },
      { lat: 36.7531, lng: 3.0688 },
      FIXTURE_STOPS[3].location,
    ],
  },
  walkLeg(FIXTURE_STOPS[3], FIXTURE_STOPS[4], 3, 120),
  walkLeg(FIXTURE_STOPS[4], FIXTURE_STOPS[5], 3, 140),
];

/**
 * A complete fixture route for `request`.
 *
 * The day-count flag is derived from the requested budget rather than
 * hardcoded, so the "this needs 2+ days" UI is reachable in the app without
 * editing this file: ask for less than the route needs and you get it.
 */
export function fixtureRoute(request: RouteRequest): RouteResponse {
  const dwell = FIXTURE_STOPS.reduce((sum, s) => sum + s.dwellMinutes, 0);
  const travel = FIXTURE_SEGMENTS.reduce((sum, s) => sum + s.durationMinutes, 0);
  const total = dwell + travel;

  return {
    id: "fa000000-0000-4000-8000-0000000000ff",
    cityId: request.cityId,
    theme: request.theme,
    timeBudgetMinutes: request.timeBudgetMinutes,
    transportMode: request.transportMode,
    stops: FIXTURE_STOPS,
    segments: FIXTURE_SEGMENTS,
    estimatedTotalDurationMinutes: total,
    dayCountFlag: total > request.timeBudgetMinutes ? 2 : 1,
    generatedAt: new Date().toISOString(),
  };
}

/**
 * `refineRoute`'s placeholder: the same route minus the dropped stops.
 *
 * Legs are rebuilt between the stops that survive rather than filtered, so a
 * route with a stop removed from the middle still has a leg into every stop
 * after the first. Filtering leaves gaps — drop two stops from the six above
 * and four stops keep only one leg between them — which is not a shape the
 * client would ever get from the real module, and building UI against it would
 * mean building against a bug.
 *
 * The rule for the rebuilt legs is the same one the Response Assembler uses:
 * same cluster means walk, a change of cluster means drive. Durations are
 * crude estimates; the real module gets them from the cached matrix.
 */
export function fixtureRefinedRoute(
  request: RouteRequest,
  dropPoiIds: string[],
): RouteResponse {
  const dropped = new Set(dropPoiIds);
  const kept = FIXTURE_STOPS.filter((s) => !dropped.has(s.poiId)).map((s, i) => ({
    ...s,
    sequenceOrder: i,
  }));

  const segments: Segment[] = [];
  for (let i = 1; i < kept.length; i++) {
    const from = kept[i - 1];
    const to = kept[i];
    const sameCluster = from.clusterId === to.clusterId;
    // Reuse the original leg's numbers when the pair is unchanged, so an
    // untouched stretch of the route reads identically before and after.
    const original = FIXTURE_SEGMENTS.find(
      (s) => s.fromPoiId === from.poiId && s.toPoiId === to.poiId,
    );
    segments.push(
      original ?? {
        mode: sameCluster ? "walk" : "drive",
        fromPoiId: from.poiId,
        toPoiId: to.poiId,
        clusterId: sameCluster ? from.clusterId : null,
        durationMinutes: sameCluster ? 6 : 14,
        distanceMeters: sameCluster ? 400 : 5_000,
        geometry: [from.location, to.location],
      },
    );
  }

  const dwell = kept.reduce((sum, s) => sum + s.dwellMinutes, 0);
  const travel = segments.reduce((sum, s) => sum + s.durationMinutes, 0);
  const total = dwell + travel;

  return {
    ...fixtureRoute(request),
    stops: kept,
    segments,
    estimatedTotalDurationMinutes: total,
    dayCountFlag: total > request.timeBudgetMinutes ? 2 : 1,
  };
}
