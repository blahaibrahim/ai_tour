/**
 * The Route Generation module's wire shapes.
 *
 * snake_case throughout, because that is what `backend/server-node/src/routes/
 * routes.ts` serializes — the boundary is not renamed on the way in. The
 * Flutter client models the same payloads in `lib/models/route.dart`; when one
 * of these changes, both move together.
 */

export type TransportMode = "walking" | "driving" | "hybrid";
export type SegmentMode = "walk" | "drive";
export type RolloutStatus = "planning" | "pilot" | "live" | string;

export interface Coordinate {
  lat: number;
  lng: number;
}

export interface City {
  id: string;
  name: string;
  name_fr: string | null;
  name_ar: string | null;
  centre: Coordinate | null;
  rollout_status: RolloutStatus;
}

export interface RouteTheme {
  key: string;
  label_en: string;
  label_fr: string | null;
  label_ar: string | null;
}

export interface RouteCategory {
  key: string;
  label_en: string;
  label_fr: string | null;
  label_ar: string | null;
  icon_ref: string | null;
  color_hex: string | null;
}

export interface RouteStop {
  poi_id: string;
  sequence_order: number;
  /** Which walkable group this stop belongs to. A change of cluster means a
   *  drive leg sits in between. */
  cluster_id: number;
  name: string;
  description: string | null;
  category_key: string;
  lat: number;
  lng: number;
  /** Expected time spent here, from `pois.avg_visit_duration_minutes`. */
  dwell_minutes: number;
  checkpoint_radius_meters: number;
  opening_hours_raw: string | null;
  photo_url: string | null;
  photo_attribution: string | null;
  photo_license: string | null;
  photo_source_url: string | null;
  ar_content_id: string | null;
  stamp_id: string | null;
}

export interface RouteSegment {
  mode: SegmentMode;
  from_poi_id: string | null;
  to_poi_id: string | null;
  cluster_id: number | null;
  duration_minutes: number;
  distance_meters: number;
  /** `[lat, lng]` pairs — the line to follow, not a straight hop. */
  geometry: [number, number][];
}

export interface GeneratedRoute {
  id: string;
  city_id: string;
  theme: string;
  time_budget_minutes: number;
  transport_mode: TransportMode;
  estimated_total_duration_minutes: number;
  /** > 1 when the module's isochrone check says the stops don't fit the
   *  budget. A scheduling consequence, not a failure — see `Notice`. */
  day_count_flag: number;
  generated_at: string | null;
  stops: RouteStop[];
  /** Replacement candidates for the review step. Same shape as a stop, but
   *  `sequence_order` is -1 and they are not part of the route. */
  alternates: RouteStop[];
  segments: RouteSegment[];
}

export interface RouteSummary {
  id: string;
  city_id: string;
  city_name: string | null;
  theme: string;
  transport_mode: TransportMode;
  time_budget_minutes: number;
  estimated_total_duration_minutes: number;
  day_count_flag: number;
  stop_count: number;
  generated_at: string | null;
}

export interface RouteProgress {
  id: string;
  route_id: string;
  status: string;
  started_at: string | null;
  last_updated_at?: string | null;
  completed_at?: string | null;
  visited_poi_ids: string[];
}

export interface PromptInterpretation {
  theme: string | null;
  category_keys: string[];
  understood: boolean;
}
