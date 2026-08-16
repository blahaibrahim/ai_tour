"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import type { AtlasWilaya } from "@/lib/atlas";

import styles from "./AlgeriaMap.module.css";

/**
 * Algeria's wilayas, shaded by how many stops each holds.
 *
 * A choropleth of one quantity, so it takes one hue in ordered steps — the
 * same validated ramp the pipeline funnel uses. Wilayas with nothing in them
 * are not "step zero of the blue ramp"; they are drawn in the neutral track
 * color, because "none" is a different statement from "few".
 *
 * The outlines come from the same `dz_wilayas.geojson` the Flutter app draws,
 * and the server assigns POIs to wilayas from that same file — so a POI can
 * never appear in a shape it isn't inside of on this map.
 *
 * It pans and zooms, because it has to: everything catalogued so far is in
 * three coastal wilayas, and Alger is about eight pixels wide at national
 * scale. Zooming moves the viewBox rather than transforming a group, so the
 * projection, the hit targets and the tooltip all stay in one coordinate
 * space and nothing has to be un-scaled by hand.
 */

interface Feature {
  properties: { code?: string | number; name?: string };
  geometry: { type: string; coordinates: unknown } | null;
}

interface Shape {
  code: string;
  name: string;
  path: string;
  /** In projected user units: [minX, minY, maxX, maxY]. Used to zoom to fit. */
  bbox: [number, number, number, number];
}

interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

const WIDTH = 1000;

/** How far in you can go. Alger is ~1.5% of the country's width. */
const MAX_ZOOM = 40;

/** Slack around a wilaya when zooming to fit it, as a fraction of its size. */
const FIT_PADDING = 0.35;

/**
 * Screen pixels the pointer must travel before a press counts as a pan rather
 * than a click. Every real press jitters by one or two.
 */
const DRAG_THRESHOLD = 4;

export function AlgeriaMap({
  wilayas,
  selected,
  onSelect,
}: {
  wilayas: AtlasWilaya[];
  selected: string | null;
  onSelect: (code: string) => void;
}) {
  const [features, setFeatures] = useState<Feature[] | null>(null);
  const [hover, setHover] = useState<{ code: string; x: number; y: number } | null>(
    null,
  );
  /** null means "the whole country" — the reset state, and the initial one. */
  const [view, setView] = useState<Box | null>(null);
  const [panning, setPanning] = useState(false);

  const boxRef = useRef<HTMLDivElement | null>(null);
  const svgRef = useRef<SVGSVGElement | null>(null);
  /**
   * The press-drag-release in progress, or the last one that finished.
   *
   * It outlives the release on purpose: `click` fires after `pointerup`, and
   * the wilaya's handler reads `panning` off it so that releasing a pan over a
   * shape does not select it. That is exactly why `down` exists as well —
   * without a flag saying the button is no longer held, every later mouse move
   * would keep panning a map nobody is dragging.
   */
  const gestureRef = useRef<{
    x0: number;
    y0: number;
    lastX: number;
    lastY: number;
    /** The button is still held. */
    down: boolean;
    /** It has travelled far enough to be a pan rather than a click. */
    panning: boolean;
  } | null>(null);

  useEffect(() => {
    let live = true;
    void (async () => {
      const response = await fetch("/dz_wilayas.geojson");
      const data = (await response.json()) as { features: Feature[] };
      if (live) setFeatures(data.features);
    })();
    return () => {
      live = false;
    };
  }, []);

  const byCode = useMemo(
    () => new Map(wilayas.map((wilaya) => [wilaya.code, wilaya])),
    [wilayas],
  );

  const { shapes, height } = useMemo(() => {
    if (!features) return { shapes: [] as Shape[], height: 600 };

    const rings: { code: string; name: string; rings: [number, number][][] }[] = [];
    let minLon = Infinity;
    let minLat = Infinity;
    let maxLon = -Infinity;
    let maxLat = -Infinity;

    for (const feature of features) {
      if (!feature.geometry) continue;
      const polygons =
        feature.geometry.type === "Polygon"
          ? [(feature.geometry.coordinates as [number, number][][])[0]]
          : feature.geometry.type === "MultiPolygon"
            ? (feature.geometry.coordinates as [number, number][][][]).map(
                (polygon) => polygon[0],
              )
            : [];
      if (polygons.length === 0) continue;

      for (const ring of polygons) {
        for (const [lon, lat] of ring) {
          if (lon < minLon) minLon = lon;
          if (lat < minLat) minLat = lat;
          if (lon > maxLon) maxLon = lon;
          if (lat > maxLat) maxLat = lat;
        }
      }
      rings.push({
        code: String(feature.properties.code ?? "").padStart(2, "0"),
        name: feature.properties.name ?? "Unknown",
        rings: polygons,
      });
    }

    // Plate carrée with a cosine correction at the middle latitude. Algeria
    // spans 18 degrees of latitude, so an uncorrected one leaves the country
    // noticeably too wide.
    const stretch = Math.cos((((minLat + maxLat) / 2) * Math.PI) / 180);
    const spanX = (maxLon - minLon) * stretch;
    const spanY = maxLat - minLat;
    const scale = WIDTH / spanX;
    const boxHeight = spanY * scale;

    const project = ([lon, lat]: [number, number]): [number, number] => [
      (lon - minLon) * stretch * scale,
      (maxLat - lat) * scale,
    ];

    return {
      height: boxHeight,
      shapes: rings.map((entry) => {
        let x0 = Infinity;
        let y0 = Infinity;
        let x1 = -Infinity;
        let y1 = -Infinity;

        const path = entry.rings
          .map((ring) => {
            const points = ring.map((point) => {
              const [x, y] = project(point);
              if (x < x0) x0 = x;
              if (y < y0) y0 = y;
              if (x > x1) x1 = x;
              if (y > y1) y1 = y;
              return `${x.toFixed(1)} ${y.toFixed(1)}`;
            });
            return `M${points.join("L")}Z`;
          })
          .join("");

        return {
          code: entry.code,
          name: entry.name,
          path,
          bbox: [x0, y0, x1, y1] as [number, number, number, number],
        };
      }),
    };
  }, [features]);

  const base: Box = useMemo(
    () => ({ x: 0, y: 0, w: WIDTH, h: height }),
    [height],
  );
  const current = view ?? base;

  /** Keep the window inside the country and within the zoom limits. */
  const clamp = useCallback(
    (next: Box): Box => {
      const w = Math.min(base.w, Math.max(base.w / MAX_ZOOM, next.w));
      const h = w * (base.h / base.w);
      return {
        w,
        h,
        x: Math.min(base.w - w, Math.max(0, next.x)),
        y: Math.min(base.h - h, Math.max(0, next.y)),
      };
    },
    [base],
  );

  /**
   * Zoom about a fixed point, so the geography under the cursor stays under
   * the cursor. `k` is applied to the *clamped* result rather than the request,
   * or the anchor drifts once a zoom is capped.
   */
  const zoomAbout = useCallback(
    (factor: number, ux: number, uy: number) => {
      setView((from) => {
        const at = from ?? base;
        const clamped = clamp({ ...at, w: at.w * factor });
        const k = clamped.w / at.w;
        return clamp({
          ...clamped,
          x: ux - (ux - at.x) * k,
          y: uy - (uy - at.y) * k,
        });
      });
    },
    [base, clamp],
  );

  /** Client coordinates -> user units, exactly, whatever the layout is doing. */
  const toUser = useCallback((clientX: number, clientY: number) => {
    const svg = svgRef.current;
    const matrix = svg?.getScreenCTM();
    if (!svg || !matrix) return null;
    // getScreenCTM accounts for preserveAspectRatio letterboxing, which a
    // getBoundingClientRect ratio would silently get wrong once max-height
    // starts clipping the map.
    return new DOMPoint(clientX, clientY).matrixTransform(matrix.inverse());
  }, []);

  // Wheel is registered by hand because React attaches it passively at the
  // root, where preventDefault does nothing and the page scrolls instead.
  useEffect(() => {
    const svg = svgRef.current;
    if (!svg) return;

    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      const point = toUser(event.clientX, event.clientY);
      if (!point) return;
      zoomAbout(Math.exp(event.deltaY * 0.0015), point.x, point.y);
    };

    svg.addEventListener("wheel", onWheel, { passive: false });
    return () => svg.removeEventListener("wheel", onWheel);
  }, [toUser, zoomAbout, features]);

  const onPointerDown = (event: React.PointerEvent<SVGSVGElement>) => {
    if (event.button !== 0) return;
    // Deliberately no setPointerCapture here. Capturing on press retargets the
    // subsequent `click` to the <svg>, so the per-wilaya onClick never fires
    // and the map becomes unselectable. Capture is taken below, only once a
    // real pan has begun — by which point there is no click to preserve.
    gestureRef.current = {
      x0: event.clientX,
      y0: event.clientY,
      lastX: event.clientX,
      lastY: event.clientY,
      down: true,
      panning: false,
    };
  };

  const endGesture = (event: React.PointerEvent<SVGSVGElement>) => {
    const gesture = gestureRef.current;
    if (!gesture?.down) return;

    // The button is up: no further movement is a drag. `panning` is left as it
    // is, for the `click` that is about to fire, and the next press replaces
    // the whole gesture anyway.
    gesture.down = false;
    gesture.lastX = event.clientX;
    gesture.lastY = event.clientY;

    if (gesture.panning) {
      setPanning(false);
      if (event.currentTarget.hasPointerCapture(event.pointerId)) {
        event.currentTarget.releasePointerCapture(event.pointerId);
      }
    }
  };

  const onPointerMove = (event: React.PointerEvent<SVGSVGElement>) => {
    const gesture = gestureRef.current;
    if (!gesture?.down) return;

    // A release that happened somewhere this element never heard about — off
    // the window, or swallowed by another handler — would otherwise leave the
    // gesture held open and the map stuck to the cursor.
    if (event.buttons === 0) {
      endGesture(event);
      return;
    }

    const dx = event.clientX - gesture.lastX;
    const dy = event.clientY - gesture.lastY;
    gesture.lastX = event.clientX;
    gesture.lastY = event.clientY;

    if (!gesture.panning) {
      // A press always jitters by a pixel or two. Below the threshold this is
      // still a click on a wilaya, not a pan — treating any movement at all as
      // a drag is what made the map impossible to select from.
      const travelled = Math.hypot(
        event.clientX - gesture.x0,
        event.clientY - gesture.y0,
      );
      if (travelled < DRAG_THRESHOLD) return;
      gesture.panning = true;
      setPanning(true);
      event.currentTarget.setPointerCapture(event.pointerId);
    }

    const matrix = svgRef.current?.getScreenCTM();
    if (!matrix) return;
    // matrix.a is screen pixels per user unit; during a pan the viewBox size
    // does not change, so it is constant for the whole gesture.
    setView((from) => {
      const at = from ?? base;
      return clamp({ ...at, x: at.x - dx / matrix.a, y: at.y - dy / matrix.d });
    });
  };

  const fitTo = useCallback(
    (bbox: [number, number, number, number]) => {
      const [x0, y0, x1, y1] = bbox;
      const padX = (x1 - x0) * FIT_PADDING;
      const padY = (y1 - y0) * FIT_PADDING;
      // Fit the wider of the two axes so the whole shape lands inside, then
      // recentre — clamp() derives the height from the country's aspect.
      const w = Math.max(x1 - x0 + padX * 2, (y1 - y0 + padY * 2) * (base.w / base.h));
      const fitted = clamp({ x: 0, y: 0, w, h: 0 });
      setView(
        clamp({
          ...fitted,
          x: (x0 + x1) / 2 - fitted.w / 2,
          y: (y0 + y1) / 2 - fitted.h / 2,
        }),
      );
    },
    [base, clamp],
  );

  const zoomed = view !== null && view.w < base.w - 0.5;
  const max = Math.max(...wilayas.map((wilaya) => wilaya.poiCount), 1);

  // Even steps across the observed range: with three seeded cities the counts
  // are lumpy, and quantiles would put "1" and "22" in the same bucket.
  const fillFor = (code: string) => {
    const count = byCode.get(code)?.poiCount ?? 0;
    if (count === 0) return "var(--data-track)";
    return `var(--data-${Math.min(5, Math.ceil((count / max) * 5))})`;
  };

  const hovered = hover ? byCode.get(hover.code) : null;
  const selectedShape = shapes.find((shape) => shape.code === selected) ?? null;

  return (
    <div className={styles.box} ref={boxRef}>
      {features === null ? (
        <p className={styles.loading}>loading boundaries…</p>
      ) : (
        <svg
          ref={svgRef}
          className={`${styles.map} ${panning ? styles.panning : ""}`}
          viewBox={`${current.x} ${current.y} ${current.w} ${current.h}`}
          role="group"
          aria-label="Algeria by wilaya, shaded by number of stops"
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={endGesture}
          onPointerCancel={endGesture}
          onLostPointerCapture={endGesture}
        >
          {shapes.map((shape) => {
            const wilaya = byCode.get(shape.code);
            const count = wilaya?.poiCount ?? 0;
            return (
              <path
                key={shape.code}
                d={shape.path}
                fill={fillFor(shape.code)}
                className={`${styles.wilaya} ${
                  selected === shape.code ? styles.selected : ""
                }`}
                tabIndex={0}
                role="button"
                aria-label={`${shape.name}, ${count} stops`}
                onClick={() => {
                  // A pan that ended over this shape is not a click on it.
                  if (gestureRef.current?.panning) return;
                  onSelect(shape.code);
                }}
                onDoubleClick={() => fitTo(shape.bbox)}
                onKeyDown={(event) => {
                  if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    onSelect(shape.code);
                  }
                }}
                onPointerMove={(event) => {
                  if (panning) return;
                  const box = boxRef.current?.getBoundingClientRect();
                  if (!box) return;
                  setHover({
                    code: shape.code,
                    x: event.clientX - box.left,
                    y: event.clientY - box.top,
                  });
                }}
                onPointerLeave={() => setHover(null)}
              />
            );
          })}
        </svg>
      )}

      {hover && hovered && !panning ? (
        <div
          className={styles.tooltip}
          style={{ left: hover.x, top: hover.y }}
          role="presentation"
        >
          <strong>{hovered.name}</strong>
          <span>
            {hovered.poiCount} {hovered.poiCount === 1 ? "stop" : "stops"}
          </span>
          {hovered.counts.clips + hovered.counts.captures > 0 ? (
            <span>
              {hovered.counts.clips} clips · {hovered.counts.captures} captures
            </span>
          ) : null}
        </div>
      ) : null}

      {features === null ? null : (
        <div className={styles.controls}>
          <button
            type="button"
            className={styles.control}
            aria-label="Zoom in"
            onClick={() =>
              zoomAbout(1 / 1.6, current.x + current.w / 2, current.y + current.h / 2)
            }
          >
            +
          </button>
          <button
            type="button"
            className={styles.control}
            aria-label="Zoom out"
            onClick={() =>
              zoomAbout(1.6, current.x + current.w / 2, current.y + current.h / 2)
            }
          >
            −
          </button>
          {selectedShape ? (
            <button
              type="button"
              className={styles.control}
              aria-label={`Zoom to ${selectedShape.name}`}
              title={`Zoom to ${selectedShape.name}`}
              onClick={() => fitTo(selectedShape.bbox)}
            >
              ⤢
            </button>
          ) : null}
          <button
            type="button"
            className={styles.control}
            aria-label="Reset the view"
            disabled={!zoomed}
            onClick={() => setView(null)}
          >
            ⌂
          </button>
        </div>
      )}

      <div className={styles.footer}>
        <div className={styles.legend}>
          <span className={styles.legendLabel}>stops</span>
          <span
            className={styles.swatch}
            style={{ background: "var(--data-track)" }}
          />
          <span className={styles.legendLabel}>0</span>
          {[1, 2, 3, 4, 5].map((step) => (
            <span
              key={step}
              className={styles.swatch}
              style={{ background: `var(--data-${step})` }}
            />
          ))}
          <span className={styles.legendLabel}>{max}</span>
        </div>
        <span className={styles.legendLabel}>
          {zoomed
            ? `${(base.w / current.w).toFixed(1)}× · drag to pan`
            : "scroll to zoom · double-click a wilaya to fit it"}
        </span>
      </div>
    </div>
  );
}
