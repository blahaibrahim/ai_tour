"use client";

import type { Feature, FeatureCollection, Geometry } from "geojson";
import type { Layer, LeafletMouseEvent, PathOptions } from "leaflet";
import L from "leaflet";
import { useEffect, useMemo, useState } from "react";
import { GeoJSON, MapContainer, TileLayer, useMap } from "react-leaflet";

import type { City } from "@/lib/types";

import "leaflet/dist/leaflet.css";
import styles from "./WilayaMap.module.css";

/**
 * The stretch of country the planner opens on: Tlemcen in the west to El Tarf
 * in the east, and inland far enough to take in Batna and Djelfa.
 *
 * The map used to open at city zoom, which meant one wilaya filled the viewport
 * and the map's own question — *which part of the country?* — could not be
 * answered without first zooming out to find the rest of it. Framing the
 * populated north means every wilaya a route can currently be built in is on
 * screen from the first frame.
 */
const NORTH_ALGERIA: L.LatLngBoundsExpression = [
  [33.6, -2.4],
  [37.3, 8.8],
];

/**
 * The planning surface: a map for orientation, with the routable wilayas
 * highlighted on it.
 *
 * The map is context, not input. Routes are scoped to a city's published POI
 * catalogue, so where the camera happens to sit does not affect what gets
 * generated — the *selection* does, and that is a click on a wilaya.
 */
export default function WilayaMapCanvas({
  cities,
  cityId,
  onSelect,
  /** Leaves room at the bottom for the planner docked over the map, so the
   *  fitted region is not hidden behind it. */
  bottomPadding = 240,
}: {
  cities: City[];
  cityId: string | null;
  onSelect: (id: string) => void;
  bottomPadding?: number;
}) {
  const [geo, setGeo] = useState<FeatureCollection<Geometry> | null>(null);

  useEffect(() => {
    let live = true;
    void fetch("/dz_wilayas.geojson")
      .then((res) => res.json())
      .then((data: FeatureCollection<Geometry>) => {
        if (live) setGeo(data);
      })
      .catch(() => {
        // A missing outline costs the highlighting, not the planner: the city
        // can still be picked from the list in the panel.
      });
    return () => {
      live = false;
    };
  }, []);

  const cityForFeature = useMemo(() => {
    const byName = new Map(cities.map((city) => [normalise(city.name), city]));
    return (feature: Feature<Geometry> | undefined) => {
      const name = (feature?.properties as { name?: string } | undefined)?.name;
      return name ? (byName.get(normalise(name)) ?? null) : null;
    };
  }, [cities]);

  const style = (feature?: Feature<Geometry>): PathOptions => {
    const city = cityForFeature(feature);
    const isSelected = city !== null && city.id === cityId;
    // A city still in `planning` is drawn as unroutable even though the API
    // lists it — offering a fill that cannot be generated is worse than not
    // offering it.
    const isRoutable = city !== null && city.rollout_status !== "planning";

    return {
      color: isSelected ? "#2f549a" : "rgba(110, 122, 147, 0.35)",
      weight: isSelected ? 2 : 1,
      fillColor: "#2f549a",
      fillOpacity: isSelected ? 0.3 : isRoutable ? 0.07 : 0,
    };
  };

  const onEachFeature = (feature: Feature<Geometry>, layer: Layer) => {
    const city = cityForFeature(feature);
    if (!city || city.rollout_status === "planning") return;

    const path = layer as L.Path;
    path.on({
      click: () => onSelect(city.id),
      mouseover: (event: LeafletMouseEvent) => {
        if (city.id === cityId) return;
        (event.target as L.Path).setStyle({ fillOpacity: 0.18 });
      },
      mouseout: (event: LeafletMouseEvent) => {
        if (city.id === cityId) return;
        (event.target as L.Path).setStyle({ fillOpacity: 0.07 });
      },
    });
    path.bindTooltip(city.name, { sticky: true, className: styles.tooltip });
  };

  return (
    <MapContainer
      className={styles.map}
      bounds={NORTH_ALGERIA}
      boundsOptions={{ paddingBottomRight: [0, bottomPadding] }}
      zoomControl={false}
      scrollWheelZoom
      minZoom={4}
      maxZoom={18}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
        url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
        subdomains={["a", "b", "c", "d"]}
      />

      {geo ? (
        // Keyed on the selection so the layer restyles when it changes:
        // `style` is read once per render of the layer, not per state update.
        <GeoJSON key={cityId ?? "none"} data={geo} style={style} onEachFeature={onEachFeature} />
      ) : null}

      <FlyToCity cities={cities} cityId={cityId} bottomPadding={bottomPadding} />
    </MapContainer>
  );
}

/**
 * Moves the camera when the *selection* moves — never the other way round.
 *
 * Reporting the camera back into the selection on every frame of a pan is what
 * the app deliberately stopped doing: it rebuilds the whole planner sixty times
 * a second, and the resulting programmatic move fights the gesture that caused
 * it.
 */
function FlyToCity({
  cities,
  cityId,
  bottomPadding,
}: {
  cities: City[];
  cityId: string | null;
  bottomPadding: number;
}) {
  const map = useMap();

  useEffect(() => {
    if (!cityId) {
      map.fitBounds(NORTH_ALGERIA, { paddingBottomRight: [0, bottomPadding] });
      return;
    }
    const centre = cities.find((c) => c.id === cityId)?.centre;
    if (!centre) return;
    map.flyTo([centre.lat, centre.lng], 10, { duration: 0.6 });
  }, [bottomPadding, cities, cityId, map]);

  return null;
}

/**
 * City names and wilaya names are the same places spelled by different sources.
 * `Algiers` is the only mismatch the catalogue actually contains; the rest
 * agree once case and accents are taken off.
 */
function normalise(name: string): string {
  const folded = name
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .trim()
    .toLowerCase();
  return folded === "algiers" ? "alger" : folded;
}
