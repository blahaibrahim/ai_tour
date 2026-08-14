/**
 * Layer 3 — Response Assembler.
 *
 * Builds the final route object: segments, mode tags, checkpoint radii
 * (spec §3). Pure — no dependencies, so it is one of the two components built
 * first (spec §9 step 4).
 *
 * The one output rule that matters downstream: **every segment carries its own
 * mode tag**. That tagging is what lets the AR/UI layer render "drive here,
 * then walk this loop" without knowing how the segment was generated
 * (spec §5). A client that has to infer the mode from cluster ids is a client
 * that will get it wrong the first time a cluster has one stop in it.
 *
 * Segment shape, per the hybrid transport model:
 *   • inter-cluster leg → mode 'drive', anchor point to anchor point,
 *     `clusterId: null`
 *   • intra-cluster leg → mode 'walk', stop to stop, `clusterId` set
 *
 * Parking availability and one-way / restricted-zone streets are explicitly
 * out of scope for the demo phase, and are isolated to the driving-segment
 * handling here and in the Adapter so that adding them later does not require
 * a redesign (spec §10). Keep that isolation.
 */
import {
  Cluster,
  Coordinate,
  Locale,
  Poi,
  RouteRequest,
  RouteResponse,
  RouteStop,
  Segment,
  SegmentMode,
  TimeEstimate,
  TransportMode,
} from "../types";

export interface AssembleInput {
  request: RouteRequest;
  orderedClusters: Cluster[];
  segments: Segment[];
  estimate: TimeEstimate;
  /** Eligible POIs the budget fit left out, best first. */
  alternates?: Poi[];
}

/**
 * One leg's measurements, as the provider returned them.
 *
 * Deviation from the original stub, which typed the inputs to `buildSegments`
 * as `Segment[]`: a provider answer has no mode and no cluster, and supplying
 * a half-filled Segment just to pass it in would mean every caller inventing
 * the two fields this function exists to set.
 */
export interface LegGeometry {
  durationSeconds: number;
  distanceMeters: number;
  geometry: Coordinate[];
  /**
   * How this hop is travelled. Only meaningful for inter-cluster legs — an
   * intra-cluster hop is walked by definition, that being what a cluster is.
   *
   * Carried per leg rather than assumed, because "between clusters" and "in a
   * car" are not the same statement. Two clusters can sit a few hundred metres
   * apart and be walked between; tagging that a drive is how a traveller ends
   * up told to drive across a square.
   */
  mode?: SegmentMode;
}

/** Spec §7, transcribed: `ResponseAssembler.assemble(...)`. */
export function assemble(input: AssembleInput): RouteResponse {
  const { request, orderedClusters, segments, estimate } = input;
  const locale = request.locale ?? "en";

  const stops: RouteStop[] = [];
  let sequenceOrder = 0;

  for (const cluster of orderedClusters) {
    for (const poi of cluster.pois) {
      stops.push(toStop(poi, sequenceOrder++, cluster.id, locale));
    }
  }

  return {
    // Provisional. RouteRepository.persist assigns the real one and the
    // orchestrator swaps it in — the row's identity comes from the database,
    // not from here.
    id: "",
    cityId: request.cityId,
    theme: request.theme,
    timeBudgetMinutes: request.timeBudgetMinutes,
    transportMode: deriveTransportMode(segments, request.transportMode),
    stops,
    segments,
    estimatedTotalDurationMinutes: estimate.totalMinutes,
    dayCountFlag: estimate.dayCountFlag,
    generatedAt: new Date().toISOString(),
    // sequenceOrder and clusterId are -1 throughout: these are candidates, not
    // positions in a route, and plausible-looking indices would invite a client
    // to render them as stops.
    alternates: (input.alternates ?? []).map((poi) => toStop(poi, -1, -1, locale)),
  };
}

/** One POI as the client renders it. Shared by the route's own stops and by the
 * alternates, so the two cannot drift into different shapes. */
function toStop(poi: Poi, sequenceOrder: number, clusterId: number, locale: Locale): RouteStop {
  return {
    poiId: poi.id,
    sequenceOrder,
    clusterId,
    name: localized(locale, poi.nameEn, poi.nameFr, poi.nameAr) ?? "Unnamed place",
    description: localized(locale, poi.descriptionEn, poi.descriptionFr, poi.descriptionAr),
    categoryKey: poi.categoryKey,
    location: poi.location,
    dwellMinutes: poi.avgVisitDurationMinutes,
    // Per-POI, never global: GPS drift in dense old-city areas makes one
    // global radius wrong in both directions (spec §10).
    checkpointRadiusMeters: poi.checkpointRadiusMeters,
    openingHoursRaw: poi.openingHoursRaw,
    photoUrl: poi.photoUrl,
    photoAttribution: poi.photoAttribution,
    photoLicense: poi.photoLicense,
    photoSourceUrl: poi.photoSourceUrl,
    arContentId: poi.arContentId,
    stampId: poi.stampId,
  };
}

/**
 * Builds the mode-tagged segment list from the ordered clusters and the
 * provider's per-leg geometry.
 *
 * `driveLegs[i]` is the hop into cluster i+1 from cluster i — named for the
 * common case, but it carries its own mode and a short one is a walk.
 * `walkLegs` is every intra-cluster hop, flattened in the same order this
 * function walks them. The orchestrator fetches them in exactly that order, and a short array
 * degrades to a zero-length straight segment rather than throwing — a missing
 * polyline should cost the map a line, not the traveller their route
 * (spec §8).
 */
export function buildSegments(
  orderedClusters: Cluster[],
  driveLegs: LegGeometry[],
  walkLegs: LegGeometry[],
): Segment[] {
  const segments: Segment[] = [];
  let driveIndex = 0;
  let walkIndex = 0;

  for (let ci = 0; ci < orderedClusters.length; ci++) {
    const current = orderedClusters[ci]!;

    if (ci > 0) {
      const previous = orderedClusters[ci - 1]!;
      const leg = driveLegs[driveIndex++];
      segments.push({
        mode: leg?.mode ?? "drive",
        // Anchor to anchor: which POI in the destination cluster is visited
        // first is a walking decision made after arrival, so a drive leg has
        // no POI endpoints.
        fromPoiId: null,
        toPoiId: null,
        clusterId: null,
        ...measurements(leg, previous.anchor, current.anchor),
      });
    }

    for (let pi = 0; pi < current.pois.length - 1; pi++) {
      const from = current.pois[pi]!;
      const to = current.pois[pi + 1]!;
      const leg = walkLegs[walkIndex++];
      segments.push({
        mode: "walk",
        fromPoiId: from.id,
        toPoiId: to.id,
        clusterId: current.id,
        ...measurements(leg, from.location, to.location),
      });
    }
  }

  return segments;
}

function measurements(
  leg: LegGeometry | undefined,
  from: Coordinate,
  to: Coordinate,
): Pick<Segment, "durationMinutes" | "distanceMeters" | "geometry"> {
  if (!leg) {
    return { durationMinutes: 0, distanceMeters: 0, geometry: [from, to] };
  }
  return {
    // Seconds are the matrix's unit and the provider's; minutes are the
    // response's. The conversion happens once, here, on the way out.
    durationMinutes: Math.round((leg.durationSeconds / 60) * 10) / 10,
    distanceMeters: Math.round(leg.distanceMeters),
    geometry: leg.geometry.length > 0 ? leg.geometry : [from, to],
  };
}

/**
 * What the route turned out to be, not what was asked for.
 *
 * A one-cluster route has no drive legs and is genuinely a walking route even
 * if `hybrid` was requested, and the header that reads this should say so.
 * The requested mode is the tie-breaker only when there are no segments at all
 * to judge from (a single-stop route).
 *
 * Note the gap this leaves: a traveller who asks for `walking` and gets a
 * two-cluster city is told `hybrid`, which is truthful but is not what they
 * asked for. Honouring a walking request by constraining the clustering is a
 * real feature and belongs upstream in the orchestrator, not in a rename here.
 */
function deriveTransportMode(segments: Segment[], requested: TransportMode): TransportMode {
  const hasDrive = segments.some((s) => s.mode === "drive");
  const hasWalk = segments.some((s) => s.mode === "walk");

  if (hasDrive && hasWalk) return "hybrid";
  if (hasDrive) return "driving";
  if (hasWalk) return "walking";
  return requested;
}

/** Falls back through the other locales rather than showing an empty card —
 * the catalogue is multilingual from the start (spec §10) but not uniformly
 * populated, and a stop with no name in the asked-for language still has one. */
function localized(
  locale: Locale,
  en: string | null,
  fr: string | null,
  ar: string | null,
): string | null {
  const byLocale: Record<Locale, string | null> = { en, fr, ar };
  const order: Locale[] =
    locale === "en" ? ["en", "fr", "ar"] : locale === "fr" ? ["fr", "en", "ar"] : ["ar", "fr", "en"];
  for (const l of order) {
    const value = byLocale[l];
    if (value && value.trim()) return value;
  }
  return null;
}
