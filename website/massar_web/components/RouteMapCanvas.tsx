"use client";

import L from "leaflet";
import { useEffect, useMemo } from "react";
import { MapContainer, Marker, Polyline, TileLayer, Tooltip, useMap } from "react-leaflet";

import type { GeneratedRoute, RouteSegment } from "@/lib/types";

import "leaflet/dist/leaflet.css";
import styles from "./RouteMap.module.css";

/**
 * A generated route: its legs as polylines, its stops as numbered pins.
 *
 * A port of `lib/widgets/route_map.dart`, keeping the two rules that make the
 * drawing honest:
 *
 *   * **The mode tag comes from the server, never from the cluster ids.** A
 *     leg is drive or walk because `segment.mode` says so. Inferring it from
 *     "did the cluster change" breaks the moment a cluster holds one stop.
 *   * **Missing geometry degrades to a straight line, and looks like one.** A
 *     leg the routing provider gave no path for is drawn dotted and thin, so
 *     the straight line reads as "we don't know the way" rather than as a
 *     claim that the road runs like that.
 */
export default function RouteMapCanvas({
  route,
  activeStopIndex = null,
  interactive = true,
  scrollZoom = false,
  showNames = false,
  onStopClick,
}: {
  route: GeneratedRoute;
  /** The stop the traveller is on: drawn larger and in the accent fill. Null on
   *  the planning surfaces, where no stop is "current" yet. */
  activeStopIndex?: number | null;
  interactive?: boolean;
  /** Off by default. A map embedded in a scrolling page that swallows the
   *  wheel traps the reader on it — dragging and the zoom buttons are the way
   *  in instead. */
  scrollZoom?: boolean;
  showNames?: boolean;
  onStopClick?: (index: number) => void;
}) {
  const bounds = useMemo(() => routeBounds(route), [route]);
  if (!bounds) return <div className={styles.empty} />;

  return (
    <MapContainer
      className={styles.map}
      bounds={bounds}
      boundsOptions={{ padding: [44, 44], maxZoom: 16.5 }}
      zoomControl={interactive}
      scrollWheelZoom={interactive && scrollZoom}
      dragging={interactive}
      doubleClickZoom={interactive}
      touchZoom={interactive}
      keyboard={interactive}
      attributionControl
    >
      {/* Both CARTO's and OpenStreetMap's terms require visible credit. */}
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
        url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
        subdomains={["a", "b", "c", "d"]}
      />

      <FitToRoute bounds={bounds} />

      {route.segments.map((segment, index) => (
        <Leg key={`${segment.mode}-${index}`} segment={segment} route={route} />
      ))}

      {route.stops.map((stop, index) => (
        <Marker
          key={stop.poi_id}
          position={[stop.lat, stop.lng]}
          icon={pinIcon(index, activeStopIndex)}
          keyboard={false}
          eventHandlers={onStopClick ? { click: () => onStopClick(index) } : undefined}
          alt={`Stop ${index + 1}, ${stop.name}`}
        >
          {showNames ? (
            <Tooltip direction="bottom" offset={[0, 14]} permanent className={styles.pinLabel}>
              {stop.name}
            </Tooltip>
          ) : null}
        </Marker>
      ))}
    </MapContainer>
  );
}

/**
 * Refits the camera when the route changes.
 *
 * `bounds` on the container applies once. Without this, refining a route —
 * which replaces its stops — leaves the camera framed on the route that is no
 * longer there.
 */
function FitToRoute({ bounds }: { bounds: L.LatLngBoundsExpression }) {
  const map = useMap();
  useEffect(() => {
    map.fitBounds(bounds, { padding: [44, 44], maxZoom: 16.5 });
  }, [map, bounds]);
  return null;
}

function Leg({ segment, route }: { segment: RouteSegment; route: GeneratedRoute }) {
  const isDrive = segment.mode === "drive";
  const hasRealGeometry = segment.geometry.length >= 2;
  const points: [number, number][] = hasRealGeometry
    ? segment.geometry
    : fallbackGeometry(segment, route);

  if (points.length < 2) return null;

  return (
    <>
      {/* A white casing under the line: without it a blue route across a blue
          bay disappears into the basemap. */}
      <Polyline positions={points} pathOptions={{ color: "#ffffff", weight: isDrive ? 10 : 9, opacity: 0.9 }} />
      <Polyline
        positions={points}
        pathOptions={{
          // Literals, not `var(--drive-color)`: Leaflet writes the colour into
          // the path's `stroke` presentation attribute, and custom properties
          // are not resolved there. These are the two route tokens by value.
          color: isDrive ? "#2f549a" : "#b5651d",
          weight: isDrive ? 5 : 4,
          lineCap: "round",
          lineJoin: "round",
          // Dotted says "approximate" without needing a legend, which is
          // exactly the claim being made about a reconstructed leg.
          dashArray: hasRealGeometry ? (isDrive ? undefined : "9 7") : "1 6",
        }}
      />
    </>
  );
}

/** The endpoints of a leg the provider gave no geometry for. */
function fallbackGeometry(segment: RouteSegment, route: GeneratedRoute): [number, number][] {
  const find = (poiId: string | null) => {
    if (!poiId) return null;
    const stop = route.stops.find((s) => s.poi_id === poiId);
    return stop ? ([stop.lat, stop.lng] as [number, number]) : null;
  };
  const from = find(segment.from_poi_id);
  const to = find(segment.to_poi_id);
  return from && to ? [from, to] : [];
}

/**
 * A numbered stop pin. Visited, current and upcoming are three different fills,
 * so the map answers "where am I on this route" at a glance.
 */
function pinIcon(index: number, activeStopIndex: number | null) {
  const isActive = activeStopIndex === index;
  const isVisited = activeStopIndex !== null && index < activeStopIndex;
  const size = isActive ? 34 : 28;
  const state = isActive ? "active" : isVisited ? "visited" : "upcoming";
  const label = isVisited
    ? '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>'
    : String(index + 1);

  return L.divIcon({
    className: styles.pinIconReset,
    html: `<span class="${styles.pin}" data-state="${state}" style="width:${size}px;height:${size}px">${label}</span>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
    tooltipAnchor: [0, size / 2],
  });
}

/**
 * Every coordinate the route touches — stop positions plus every vertex of
 * every leg.
 *
 * The legs matter: a drive that arcs around a bay leaves the box drawn from its
 * endpoints alone, and the middle of the route would sit off screen.
 */
function routeBounds(route: GeneratedRoute): L.LatLngBoundsExpression | null {
  const points: [number, number][] = [
    ...route.stops.map((s) => [s.lat, s.lng] as [number, number]),
    ...route.segments.flatMap((s) => s.geometry),
  ];
  if (points.length === 0) return null;

  // One point has no extent, and a bounds of one point resolves to the maximum
  // zoom — a street-level view of a single pin with nothing to orient by.
  if (points.length === 1) {
    const [lat, lng] = points[0];
    return [
      [lat - 0.004, lng - 0.004],
      [lat + 0.004, lng + 0.004],
    ];
  }

  return L.latLngBounds(points.map(([lat, lng]) => L.latLng(lat, lng)));
}
