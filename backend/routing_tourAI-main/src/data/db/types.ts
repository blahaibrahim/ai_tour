import type { ColumnType, Insertable, Selectable, Updateable, JSONColumnType } from 'kysely';

export interface DB {
  regions: RegionsTable;
  cities: CitiesTable;
  categories: CategoriesTable;
  pois: PoisTable;
  routes: RoutesTable;
  route_stops: RouteStopsTable;
  progress: ProgressTable;
  progress_events: ProgressEventsTable;
}

export type RolloutStatus = 'planning' | 'pilot' | 'active';
export type RoutingProvider = 'graphhopper' | 'ors' | 'self_hosted_osrm' | 'self_hosted_graphhopper' | 'self_hosted_valhalla';
export type PoiSource = 'team_seeded' | 'api_seeded' | 'user_submitted' | 'ministry_provided';
export type PoiStatus = 'draft' | 'verified' | 'published';
export type TransportMode = 'walking' | 'driving' | 'hybrid';
export type ProgressStatus = 'in_progress' | 'completed' | 'abandoned';

export interface RegionsTable {
  id: ColumnType<string, string | undefined, never>;
  name: string;
  name_ar: string | null;
  created_at: ColumnType<Date, Date | undefined, never>;
}
export type Region = Selectable<RegionsTable>;

export interface CitiesTable {
  id: ColumnType<string, string | undefined, never>;
  region_id: string | null;
  name: string;
  name_ar: string | null;
  name_fr: string | null;
  bounding_box: string | null; // PostGIS Geography representation
  cluster_radius_meters: ColumnType<number, number | undefined, number>;
  active_routing_provider: ColumnType<RoutingProvider, RoutingProvider | undefined, RoutingProvider>;
  rollout_status: ColumnType<RolloutStatus, RolloutStatus | undefined, RolloutStatus>;
  feature_flags: ColumnType<Record<string, unknown>, string | Record<string, unknown>, string | Record<string, unknown>>;
  created_at: ColumnType<Date, Date | undefined, never>;
  updated_at: ColumnType<Date, Date | undefined, Date>;
  deleted_at: string | null;
}
export type CityRow = Selectable<CitiesTable>;

export interface CategoriesTable {
  id: ColumnType<string, string | undefined, never>;
  key: string;
  label_fr: string;
  label_ar: string;
  label_en: string;
  icon_ref: string | null;
  color_hex: string | null;
}
export type CategoryRow = Selectable<CategoriesTable>;

export interface PoisTable {
  id: ColumnType<string, string | undefined, never>;
  city_id: string;
  category_id: string;
  name_fr: string | null;
  name_ar: string | null;
  name_en: string | null;
  description_fr: string | null;
  description_ar: string | null;
  description_en: string | null;
  location: string | unknown; // PostGIS Geometry/Geography read via ST_X/ST_Y
  opening_hours_raw: string | null;
  avg_visit_duration_minutes: ColumnType<number, number | undefined, number>;
  checkpoint_radius_meters: ColumnType<number, number | undefined, number>;
  ar_content_id: string | null;
  stamp_id: string | null;
  external_ref: string | null;
  source: ColumnType<PoiSource, PoiSource | undefined, PoiSource>;
  status: ColumnType<PoiStatus, PoiStatus | undefined, PoiStatus>;
  verified_by: string | null;
  created_at: ColumnType<Date, Date | undefined, never>;
  updated_at: ColumnType<Date, Date | undefined, Date>;
  deleted_at: string | null;
}
export type PoiRow = Selectable<PoisTable>;
export type NewPoi = Insertable<PoisTable>;

export interface RoutesTable {
  id: ColumnType<string, string | undefined, never>;
  city_id: string;
  session_id: string | null;
  user_id: string | null;
  theme: string;
  time_budget_minutes: number;
  transport_mode: ColumnType<TransportMode, TransportMode | undefined, TransportMode>;
  segments: JSONColumnType<unknown[]>;
  estimated_total_duration_minutes: number;
  day_count_flag: ColumnType<number, number | undefined, number>;
  generated_at: ColumnType<Date, Date | undefined, never>;
}
export type RouteRow = Selectable<RoutesTable>;
export type NewRoute = Insertable<RoutesTable>;

export interface RouteStopsTable {
  id: ColumnType<string, string | undefined, never>;
  route_id: string;
  poi_id: string;
  sequence_order: number;
  cluster_id: number;
}
export type RouteStopRow = Selectable<RouteStopsTable>;
export type NewRouteStop = Insertable<RouteStopsTable>;

export interface ProgressTable {
  id: ColumnType<string, string | undefined, never>;
  route_id: string;
  status: ColumnType<ProgressStatus, ProgressStatus | undefined, ProgressStatus>;
  started_at: ColumnType<Date, Date | undefined, never>;
  last_updated_at: ColumnType<Date, Date | undefined, Date>;
  completed_at: Date | null;
}

export interface ProgressEventsTable {
  id: ColumnType<string, string | undefined, never>;
  progress_id: string;
  poi_id: string;
  arrived_at: ColumnType<Date, Date | undefined, never>;
}
