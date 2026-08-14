import type { Coordinate } from './coordinate.model.js';

/**
 * Domain-level POI shape used by routing algorithms (Clustering Engine,
 * Route Optimizer, Time & Reachability Estimator).
 *
 * Intentionally a subset of the `pois` table (Section 7) — fields that
 * matter only for persistence, moderation, or bookkeeping (source,
 * verified_by, external_ref, timestamps, deleted_at) stay in the Data
 * layer's row type and never reach Domain. POI Repository is responsible
 * for narrowing a full DB row down to this shape.
 */
export interface Poi {
  id: string;
  cityId: string;
  categoryId: string;
  nameFr: string | null;
  nameAr: string | null;
  nameEn: string | null;
  location: Coordinate;
  /** Raw OSM opening_hours syntax (Section 10) — parsed by POI Selector. */
  openingHoursRaw: string | null;
  avgVisitDurationMinutes: number;
  /**
   * GAP FLAG: not present in the `pois` table as specified in Section 7,
   * but required by the Response Assembler's checkpoint output (Section
   * 8) and Section 10's "checkpoint radius is per-POI configurable, not
   * global." Recommend adding `checkpoint_radius_meters INT NOT NULL
   * DEFAULT 30` to the `pois` migration in Section 7. Left required (not
   * optional) here so a missing value surfaces as a type error wherever
   * a POI is constructed, instead of a silent runtime gap.
   */
  checkpointRadiusMeters: number;
}
