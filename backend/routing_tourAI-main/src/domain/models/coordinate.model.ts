/**
 * A single geographic point, always expressed as named lat/lng fields.
 *
 * Design note: PostGIS (GEOGRAPHY columns) and GeoJSON both use
 * [longitude, latitude] tuple order, a well-known source of bugs. The
 * Domain and Adapter layers never pass raw [number, number] tuples to
 * each other — only this named-field shape. Conversion to/from PostGIS's
 * lon/lat tuple order happens at the Data layer boundary (POI
 * Repository); conversion to/from whatever order a given routing
 * provider's SDK expects happens inside that provider's own Adapter
 * implementation. Domain code never has to remember which order is which.
 */
export interface Coordinate {
  lat: number;
  lng: number;
}

/**
 * Minimal GeoJSON Polygon geometry, used for isochrone results.
 *
 * GraphHopper and OpenRouteService (Section 6) both return isochrones as
 * GeoJSON polygons, so this format is adopted as-is rather than invented
 * — and it plugs directly into point-in-polygon libraries (e.g. Turf.js)
 * for the Time & Reachability Estimator's day-count check (Section 5).
 *
 * `coordinates` follows the GeoJSON spec: an array of linear rings, each
 * ring an array of [lng, lat] positions — first ring is the exterior
 * boundary, further rings (if any) are holes.
 */
export interface GeoJsonPolygon {
  type: 'Polygon';
  coordinates: number[][][];
}
