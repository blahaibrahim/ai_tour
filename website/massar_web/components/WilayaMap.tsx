"use client";

import dynamic from "next/dynamic";

import type { City } from "@/lib/types";

/** Browser-only, for the same reason as `RouteMap`: Leaflet touches `window`
 *  at import time, and `ssr: false` is only legal inside a Client Component. */
const WilayaMapCanvas = dynamic(() => import("./WilayaMapCanvas"), {
  ssr: false,
  loading: () => <div style={{ width: "100%", height: "100%", background: "var(--surface-alt)" }} />,
});

export default function WilayaMap(props: {
  cities: City[];
  cityId: string | null;
  onSelect: (id: string) => void;
  bottomPadding?: number;
}) {
  return <WilayaMapCanvas {...props} />;
}
