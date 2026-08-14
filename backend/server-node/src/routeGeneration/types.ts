/**
 * Route Generation Module — shared contracts (Technical Design Spec §7).
 *
 * These are the seams the spec's layering depends on. Nothing here imports a
 * provider SDK, a database client, or an HTTP framework: Layer 3 (Domain) is
 * specified to be pure, and it can only stay pure if the types it speaks are.
 *
 * The interface contracts in §7 are transcribed as written. Where this file
 * adds something the spec does not name, the addition is marked NOT IN SPEC
 * with the reason — do not treat those as agreed.
 */

// --- primitives -------------------------------------------------------------

export interface Coordinate {
  lat: number;
  lng: number;
}

/** The traveller's requested transport model for the whole route. */
export type TransportMode = "walking" | "driving" | "hybrid";

/** The mode of one leg. Distinct from TransportMode: a `hybrid` route is
 * made of legs that are individually `drive` or `walk`. */
export type SegmentMode = "drive" | "walk";

/** The profile passed to the routing provider. */
export type RoutingProfile = "walking" | "driving";

export type RolloutStatus = "planning" | "pilot" | "active";

export type RoutingProviderName =
  | "graphhopper"
  | "ors"
  | "self_hosted_osrm"
  | "self_hosted_graphhopper"
  | "self_hosted_valhalla";

export type PoiSource = "team_seeded" | "api_seeded" | "user_submitted" | "ministry_provided";
export type PoiStatus = "draft" | "verified" | "published";
export type ProgressStatus = "in_progress" | "completed" | "abandoned";

/** Supported content locales. Multilingual fields are required from the start
 * (spec §10), so nothing here falls back to a single language. */
export type Locale = "en" | "fr" | "ar";

// --- data records (Layer 5 shapes) ------------------------------------------

export interface Category {
  id: string;
  key: string;
  labelEn: string;
  labelFr: string;
  labelAr: string;
  iconRef: string | null;
  colorHex: string | null;
}

/**
 * A theme, as the request builder's chips render it.
 *
 * NOT IN SPEC — §7's schema has no themes table: `routes` stores a `theme`
 * string and `pois` carry a `category_id`, with nothing joining them. The
 * mapping has to live somewhere, and a table (`themes` + `theme_categories`,
 * migration 20260814102500) keeps the "config, not code changes" property §2
 * rests on, which a constant in the codebase would not.
 */
export interface Theme {
  key: string;
  labelEn: string;
  labelFr: string;
  labelAr: string;
}

export interface Poi {
  id: string;
  cityId: string;
  categoryId: string;
  categoryKey: string;
  nameEn: string | null;
  nameFr: string | null;
  nameAr: string | null;
  descriptionEn: string | null;
  descriptionFr: string | null;
  descriptionAr: string | null;
  location: Coordinate;
  /** OSM `opening_hours` syntax, parseable — never free text (spec §10). */
  openingHoursRaw: string | null;
  /** Dwell time. The Time Estimator sums these alongside travel time. */
  avgVisitDurationMinutes: number;
  /** Per-POI, not global — GPS drift in dense old-city areas makes one global
   * radius wrong in both directions (spec §10). */
  checkpointRadiusMeters: number;
  arContentId: string | null;
  stampId: string | null;
  externalRef: string | null;
  source: PoiSource;
  status: PoiStatus;
  photoUrl: string | null;
  photoAttribution: string | null;
  photoLicense: string | null;
  photoSourceUrl: string | null;
  /**
   * How much this place is worth visiting, roughly 0–100, from the ingestion
   * pipeline's scoring. Null for anything never scored — hand-authored rows —
   * which the budget fit treats as mid-ranked rather than worthless.
   */
  interestScore: number | null;
}

export interface CityConfig {
  id: string;
  regionId: string | null;
  name: string;
  nameFr: string | null;
  nameAr: string | null;
  /** Centre of `bounding_box`, for centring the map. */
  centre: Coordinate | null;
  /** Drives the Clustering Engine. Default 500 m, expected to need per-city
   * tuning once real pilot data exists (spec §10). */
  clusterRadiusMeters: number;
  activeRoutingProvider: RoutingProviderName;
  rolloutStatus: RolloutStatus;
  featureFlags: Record<string, unknown>;
}

// --- domain shapes (Layer 3) ------------------------------------------------

/** A group of POIs close enough to walk between. Produced by the Clustering
 * Engine, consumed by the Route Optimizer. */
export interface Cluster {
  /** Stable within one generation only — matches `route_stops.cluster_id`. */
  id: number;
  pois: Poi[];
  /** The point the driving legs route to. */
  anchor: Coordinate;
}

/**
 * All-pairs travel durations in seconds, indexed by position in the points
 * array the matrix was built from. `null` marks an unroutable pair.
 *
 * The efficiency rule the whole layer turns on: this is fetched with ONE
 * provider call covering every cluster and stop pair, never one call per pair
 * (spec §4).
 */
export interface DurationMatrix {
  /** `durations[i][j]` — seconds from points[i] to points[j]. */
  durations: Array<Array<number | null>>;
  /** The points the indices refer to, in order. */
  points: Coordinate[];
  /** Metres, when the provider returns them. Ordering uses durations. */
  distances?: Array<Array<number | null>>;
}

/** GeoJSON-style polygon ring(s) of the area reachable in the queried budget. */
export interface IsochronePolygon {
  /** Outer ring first, in [lng, lat] order to match GeoJSON. */
  coordinates: Array<Array<[number, number]>>;
  timeBudgetMinutes: number;
  mode: RoutingProfile;
}

/** One provider `getRoute` answer, normalized. */
export interface RouteResult {
  durationSeconds: number;
  distanceMeters: number;
  /** Decoded polyline, in order. Empty when the provider returned none. */
  geometry: Coordinate[];
}

/**
 * One leg of the finished route.
 *
 * `mode` is the field the AR/UI layer renders "drive here, then walk this
 * loop" from — it must never have to infer the mode from how the segment was
 * generated (spec §5).
 */
export interface Segment {
  mode: SegmentMode;
  fromPoiId: string | null;
  toPoiId: string | null;
  /** Which cluster this leg is inside; null for an inter-cluster drive. */
  clusterId: number | null;
  durationMinutes: number;
  distanceMeters: number;
  geometry: Coordinate[];
}

export interface TimeEstimate {
  totalMinutes: number;
  /** 1 normally; 2+ when an isochrone check says the remaining POIs fall
   * outside the area reachable in the remaining budget (spec §5). */
  dayCountFlag: number;
}

// --- request / response (Layer 1 <-> Layer 2) -------------------------------

export interface RouteRequest {
  cityId: string;
  theme: string;
  timeBudgetMinutes: number;
  transportMode: TransportMode;
  /** NOT IN SPEC. §3 says the POI Selector filters "by theme, category, and
   * city", but §7's request carries only a theme — leaving no way to express
   * the category filter. Optional, so a theme-only request is unchanged. */
  categoryKeys?: string[];
  /** Which language the assembled names/descriptions come back in. */
  locale?: Locale;
  /** Nullable per the schema: supports anonymous demo usage. */
  userId?: string | null;
  sessionId?: string | null;
}

/** One stop, as the client renders it. Flattens the POI fields the UI needs so
 * the app does not have to hold a second POI cache. */
export interface RouteStop {
  poiId: string;
  sequenceOrder: number;
  clusterId: number;
  name: string;
  description: string | null;
  categoryKey: string;
  location: Coordinate;
  dwellMinutes: number;
  checkpointRadiusMeters: number;
  openingHoursRaw: string | null;
  photoUrl: string | null;
  photoAttribution: string | null;
  photoLicense: string | null;
  photoSourceUrl: string | null;
  arContentId: string | null;
  stampId: string | null;
}

/** What the Response Assembler builds and Layer 1 serializes. */
export interface RouteResponse {
  id: string;
  cityId: string;
  theme: string;
  timeBudgetMinutes: number;
  transportMode: TransportMode;
  stops: RouteStop[];
  segments: Segment[];
  estimatedTotalDurationMinutes: number;
  dayCountFlag: number;
  generatedAt: string;
  /**
   * Eligible POIs that did not make the budget, best first.
   *
   * NOT IN SPEC. The app lets a traveller reject stops during review, and
   * every rejection takes the route further under the budget they asked for —
   * with nothing to offer in its place, because the response only ever carried
   * the stops it had chosen. These are the next-best candidates, so a rejected
   * stop can be replaced rather than simply lost.
   *
   * Not part of the route: no ordering, no segments, and `sequenceOrder` is
   * -1. They become real stops only if the client sends them back through a
   * generate call.
   */
  alternates: RouteStop[];
}

// --- progress ---------------------------------------------------------------

export interface Progress {
  id: string;
  routeId: string;
  status: ProgressStatus;
  startedAt: string;
  lastUpdatedAt: string;
  completedAt: string | null;
  /** POI ids already checkpointed, oldest first. */
  visitedPoiIds: string[];
}

export interface ProgressEvent {
  id: string;
  progressId: string;
  poiId: string;
  arrivedAt: string;
}
