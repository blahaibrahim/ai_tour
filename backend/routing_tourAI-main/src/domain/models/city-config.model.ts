/** Matches the `routing_provider` enum (Section 7). */
export type RoutingProviderName =
  | 'graphhopper'
  | 'ors'
  | 'self_hosted_osrm'
  | 'self_hosted_graphhopper'
  | 'self_hosted_valhalla';

/** Matches the `rollout_status` enum (Section 7). */
export type RolloutStatus = 'planning' | 'pilot' | 'active';

/**
 * Per-city settings that drive routing behavior without a code change
 * (Section 2: "City-level configuration... drives behavior without code
 * changes — the mechanism behind the phased city rollout"). Loaded once
 * per request by the Orchestrator; cached in memory with a short refresh
 * interval by City Config Repository (Section 3).
 */
export interface CityConfig {
  id: string;
  name: string;
  nameAr: string | null;
  nameFr: string | null;
  clusterRadiusMeters: number;
  activeRoutingProvider: RoutingProviderName;
  rolloutStatus: RolloutStatus;
  /** Untyped by design — see the feature_flags JSONB column, Section 7. */
  featureFlags: Record<string, unknown>;
}
