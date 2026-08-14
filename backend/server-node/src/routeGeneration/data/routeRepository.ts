/**
 * Layer 5 — Route / Progress Repository.
 *
 * Immutable route definitions kept strictly separate from mutable progress
 * state (spec §3). A route is written once at generation and never updated;
 * everything that changes as the traveller walks lives in `progress` and the
 * append-only `progress_events`.
 *
 * That separation is what makes `route_stops` safe to query for the
 * data-flywheel work later — "which POIs actually appear in routes" is a fact
 * about the generated route, not about anyone's walk.
 *
 * ## Why this file holds the service_role client
 *
 * `route_stops` grants nothing to anon/authenticated and carries no RLS policy
 * (see its table comment) — it is server-owned by design. `routes`, `progress`
 * and `progress_events` all have SELECT policies but no INSERT policy, so
 * every write here is a service_role write too.
 *
 * The cost of that is exact and worth naming: service_role bypasses RLS, so
 * the `routes_own` policy stops protecting reads made through this client. The
 * ownership check therefore has to be written out in `findById` rather than
 * inherited. It is the one place in this module where forgetting a `where`
 * clause is a data leak instead of a bug.
 */
import type { SupabaseClient } from "@supabase/supabase-js";

import { getAdminClient } from "../../ingestion/supabaseAdmin";
import { getLogger } from "../../logger";
import { unwrap } from "../../supabase";
import {
  Locale,
  Progress,
  ProgressEvent,
  ProgressStatus,
  RouteResponse,
  RouteStop,
  Segment,
  TransportMode,
} from "../types";

const logger = getLogger("routeGeneration.routeRepository");

export interface PersistRouteInput {
  route: RouteResponse;
  userId: string | null;
  sessionId: string | null;
}

export interface RouteRepository {
  /**
   * Writes the `routes` row and its `route_stops` children in one transaction.
   * Returns the persisted id — which becomes `RouteResponse.id`, so the
   * assembler's provisional id is replaced here rather than the other way
   * round.
   */
  persist(input: PersistRouteInput): Promise<string>;

  /** Rehydrates a route, joining `route_stops` back onto `pois`. */
  findById(routeId: string, userId: string | null, locale?: Locale): Promise<RouteResponse | null>;

  /** The caller's most recent route — what "resume my tour" reads. */
  findLatestForUser(userId: string, locale?: Locale): Promise<RouteResponse | null>;
}

export interface ProgressRepository {
  start(routeId: string): Promise<Progress>;
  findById(progressId: string): Promise<Progress | null>;
  findByRouteId(routeId: string): Promise<Progress | null>;

  /**
   * Appends a checkpoint. Append-only by design: an arrival is an event that
   * happened, not a flag to be toggled, and re-arriving at a stop is a real
   * thing that should not overwrite the first visit.
   *
   * Whether the traveller was actually inside `checkpoint_radius_meters` is
   * decided by the separate AR trigger service, along with the
   * dwell-time-before-confirm logic (spec §10) — this only records it.
   */
  recordCheckpoint(progressId: string, poiId: string): Promise<ProgressEvent>;

  updateStatus(progressId: string, status: Progress["status"]): Promise<Progress>;
}

interface RouteRow {
  id: string;
  city_id: string;
  theme: string;
  time_budget_minutes: number;
  transport_mode: string;
  segments: unknown;
  estimated_total_duration_minutes: number;
  day_count_flag: number;
  generated_at: string;
}

/** One row as `public.route_stops_expanded` returns it. */
interface StopRow {
  poi_id: string;
  sequence_order: number;
  cluster_id: number;
  category_key: string;
  name_en: string | null;
  name_fr: string | null;
  name_ar: string | null;
  description_en: string | null;
  description_fr: string | null;
  description_ar: string | null;
  lat: number;
  lng: number;
  avg_visit_duration_minutes: number;
  checkpoint_radius_meters: number;
  opening_hours_raw: string | null;
  ar_content_id: string | null;
  stamp_id: string | null;
  photo_url: string | null;
  photo_attribution: string | null;
  photo_license: string | null;
  photo_source_url: string | null;
}

/** Falls back through the other locales rather than showing an empty card —
 * the catalogue is multilingual from the start (spec §10) but not uniformly
 * populated, and a stop with no name in the asked-for language still has one. */
function localized(
  locale: Locale,
  values: { en: string | null; fr: string | null; ar: string | null },
): string | null {
  const order: Locale[] = locale === "en" ? ["en", "fr", "ar"] : locale === "fr" ? ["fr", "en", "ar"] : ["ar", "fr", "en"];
  for (const l of order) {
    const v = values[l];
    if (v && v.trim()) return v;
  }
  return null;
}

function rowToStop(row: StopRow, locale: Locale): RouteStop {
  return {
    poiId: row.poi_id,
    sequenceOrder: row.sequence_order,
    clusterId: row.cluster_id,
    name:
      localized(locale, { en: row.name_en, fr: row.name_fr, ar: row.name_ar }) ?? "Unnamed place",
    description: localized(locale, {
      en: row.description_en,
      fr: row.description_fr,
      ar: row.description_ar,
    }),
    categoryKey: row.category_key,
    location: { lat: row.lat, lng: row.lng },
    dwellMinutes: row.avg_visit_duration_minutes,
    checkpointRadiusMeters: row.checkpoint_radius_meters,
    openingHoursRaw: row.opening_hours_raw,
    photoUrl: row.photo_url,
    photoAttribution: row.photo_attribution,
    photoLicense: row.photo_license,
    photoSourceUrl: row.photo_source_url,
    arContentId: row.ar_content_id,
    stampId: row.stamp_id,
  };
}

class SupabaseRouteRepository implements RouteRepository {
  private get db(): SupabaseClient {
    return getAdminClient();
  }

  async persist(input: PersistRouteInput): Promise<string> {
    const { route, userId, sessionId } = input;

    const inserted = await unwrap<Array<{ id: string }>>(
      this.db
        .from("routes")
        .insert({
          city_id: route.cityId,
          session_id: sessionId,
          user_id: userId,
          theme: route.theme,
          time_budget_minutes: route.timeBudgetMinutes,
          transport_mode: route.transportMode,
          segments: route.segments,
          estimated_total_duration_minutes: route.estimatedTotalDurationMinutes,
          day_count_flag: route.dayCountFlag,
        })
        .select("id"),
    );

    const routeId = inserted?.[0]?.id;
    if (!routeId) throw new Error("routes insert returned no id");

    if (route.stops.length > 0) {
      try {
        await unwrap(
          this.db.from("route_stops").insert(
            route.stops.map((s) => ({
              route_id: routeId,
              poi_id: s.poiId,
              sequence_order: s.sequenceOrder,
              cluster_id: s.clusterId,
            })),
          ),
        );
      } catch (error) {
        // PostgREST has no transactions, so the two inserts cannot be atomic
        // from here. A route row with no stops is worse than no row at all —
        // it is a route that reads as empty rather than as missing — so the
        // parent is removed on failure. If this compensation also fails the
        // orphan is logged loudly rather than swallowed; making this properly
        // atomic means moving the write into a SECURITY DEFINER function.
        const undo = await this.db.from("routes").delete().eq("id", routeId);
        if (undo.error) {
          logger.error(
            `Orphaned route ${routeId}: stop insert failed and the compensating ` +
              `delete failed too (${undo.error.message}). Needs manual cleanup.`,
          );
        }
        throw error;
      }
    }

    return routeId;
  }

  async findById(
    routeId: string,
    userId: string | null,
    locale: Locale = "en",
  ): Promise<RouteResponse | null> {
    const rows = await unwrap<RouteRow[]>(
      this.db.from("routes").select("*").eq("id", routeId).limit(1),
    );
    const row = rows?.[0];
    if (!row) return null;

    // Written out because service_role bypasses the `routes_own` RLS policy —
    // see the note at the top of this file. Anonymous routes (user_id null)
    // stay readable, which is what "supports anonymous demo usage" asks for.
    const owner = (row as RouteRow & { user_id: string | null }).user_id;
    if (owner !== null && owner !== userId) return null;

    return this.hydrate(row, locale);
  }

  async findLatestForUser(userId: string, locale: Locale = "en"): Promise<RouteResponse | null> {
    const rows = await unwrap<RouteRow[]>(
      this.db
        .from("routes")
        .select("*")
        .eq("user_id", userId)
        .order("generated_at", { ascending: false })
        .limit(1),
    );
    const row = rows?.[0];
    return row ? this.hydrate(row, locale) : null;
  }

  private async hydrate(row: RouteRow, locale: Locale): Promise<RouteResponse> {
    const stopRows =
      (await unwrap<StopRow[]>(
        this.db.rpc("route_stops_expanded", { p_route_id: row.id }),
      )) ?? [];

    return {
      id: row.id,
      cityId: row.city_id,
      theme: row.theme,
      timeBudgetMinutes: row.time_budget_minutes,
      transportMode: row.transport_mode as TransportMode,
      stops: stopRows.map((s) => rowToStop(s, locale)),
      segments: (row.segments ?? []) as Segment[],
      estimatedTotalDurationMinutes: row.estimated_total_duration_minutes,
      dayCountFlag: row.day_count_flag,
      generatedAt: row.generated_at,
      // Not persisted: alternates are a property of the moment a route was
      // generated — which POIs the budget could not fit *then* — and re-deriving
      // them on read would answer a question nobody asked. A rehydrated route
      // is one being walked, not one being reviewed.
      alternates: [],
    };
  }
}

interface ProgressRow {
  id: string;
  route_id: string;
  status: string;
  started_at: string;
  last_updated_at: string;
  completed_at: string | null;
}

class SupabaseProgressRepository implements ProgressRepository {
  private get db(): SupabaseClient {
    return getAdminClient();
  }

  async start(routeId: string): Promise<Progress> {
    // One walk per route: restarting a tour resumes it rather than forking a
    // second progress row whose events would silently diverge from the first.
    const existing = await this.findByRouteId(routeId);
    if (existing) return existing;

    const rows = await unwrap<ProgressRow[]>(
      this.db.from("progress").insert({ route_id: routeId }).select("*"),
    );
    const row = rows?.[0];
    if (!row) throw new Error("progress insert returned no row");
    return { ...rowToProgress(row), visitedPoiIds: [] };
  }

  async findById(progressId: string): Promise<Progress | null> {
    const rows = await unwrap<ProgressRow[]>(
      this.db.from("progress").select("*").eq("id", progressId).limit(1),
    );
    const row = rows?.[0];
    return row ? { ...rowToProgress(row), visitedPoiIds: await this.visited(row.id) } : null;
  }

  async findByRouteId(routeId: string): Promise<Progress | null> {
    const rows = await unwrap<ProgressRow[]>(
      this.db
        .from("progress")
        .select("*")
        .eq("route_id", routeId)
        .order("started_at", { ascending: false })
        .limit(1),
    );
    const row = rows?.[0];
    return row ? { ...rowToProgress(row), visitedPoiIds: await this.visited(row.id) } : null;
  }

  async recordCheckpoint(progressId: string, poiId: string): Promise<ProgressEvent> {
    const rows = await unwrap<
      Array<{ id: string; progress_id: string; poi_id: string; arrived_at: string }>
    >(
      this.db
        .from("progress_events")
        .insert({ progress_id: progressId, poi_id: poiId })
        .select("id, progress_id, poi_id, arrived_at"),
    );
    const row = rows?.[0];
    if (!row) throw new Error("progress_events insert returned no row");

    // The walk is demonstrably still happening; without this `last_updated_at`
    // only ever records when it started.
    await unwrap(
      this.db
        .from("progress")
        .update({ last_updated_at: new Date().toISOString() })
        .eq("id", progressId),
    );

    return {
      id: row.id,
      progressId: row.progress_id,
      poiId: row.poi_id,
      arrivedAt: row.arrived_at,
    };
  }

  async updateStatus(progressId: string, status: Progress["status"]): Promise<Progress> {
    const now = new Date().toISOString();
    const rows = await unwrap<ProgressRow[]>(
      this.db
        .from("progress")
        .update({
          status,
          last_updated_at: now,
          completed_at: status === "completed" ? now : null,
        })
        .eq("id", progressId)
        .select("*"),
    );
    const row = rows?.[0];
    if (!row) throw new Error(`no progress row ${progressId}`);
    return { ...rowToProgress(row), visitedPoiIds: await this.visited(row.id) };
  }

  /** Checkpointed POI ids, oldest first. Deduplicated: `progress_events` is
   * append-only so a re-visit is a second row, but the client reads this as a
   * set of "places seen". */
  private async visited(progressId: string): Promise<string[]> {
    const rows =
      (await unwrap<Array<{ poi_id: string }>>(
        this.db
          .from("progress_events")
          .select("poi_id")
          .eq("progress_id", progressId)
          .order("arrived_at", { ascending: true }),
      )) ?? [];
    return [...new Set(rows.map((r) => r.poi_id))];
  }
}

function rowToProgress(row: ProgressRow): Omit<Progress, "visitedPoiIds"> {
  return {
    id: row.id,
    routeId: row.route_id,
    status: row.status as ProgressStatus,
    startedAt: row.started_at,
    lastUpdatedAt: row.last_updated_at,
    completedAt: row.completed_at,
  };
}

let sharedRoutes: RouteRepository | null = null;
let sharedProgress: ProgressRepository | null = null;

export function getRouteRepository(): RouteRepository {
  if (sharedRoutes === null) sharedRoutes = new SupabaseRouteRepository();
  return sharedRoutes;
}

export function getProgressRepository(): ProgressRepository {
  if (sharedProgress === null) sharedProgress = new SupabaseProgressRepository();
  return sharedProgress;
}
