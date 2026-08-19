"use client";

import dynamic from "next/dynamic";

import type { GeneratedRoute } from "@/lib/types";

/**
 * The route map, loaded only in the browser.
 *
 * Leaflet reaches for `window` at import time, so it cannot be part of a server
 * render. `ssr: false` is legal only inside a Client Component, which is the
 * whole reason this one-line wrapper exists.
 */
const RouteMapCanvas = dynamic(() => import("./RouteMapCanvas"), {
  ssr: false,
  loading: () => <div style={{ width: "100%", height: "100%", background: "var(--surface-alt)" }} />,
});

export default function RouteMap(props: {
  route: GeneratedRoute;
  activeStopIndex?: number | null;
  interactive?: boolean;
  scrollZoom?: boolean;
  showNames?: boolean;
  onStopClick?: (index: number) => void;
}) {
  return <RouteMapCanvas {...props} />;
}
