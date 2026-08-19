import type { CSSProperties, ReactNode } from "react";

import styles from "./GlassSurface.module.css";

/**
 * Which side of the palette the pane tints toward: `light` for chrome over the
 * app's warm page background, `dark` for chrome over photos, maps and the deep
 * backdrop, where a light tint washes out.
 */
export type GlassTint = "light" | "dark";

/**
 * A frosted pane: blurs whatever is behind it, tints it translucently, and
 * carries a thin bright edge so it reads as glass rather than as a flat tinted
 * rectangle.
 *
 * The app's `GlassSurface` is what the planner panel, the history cards and
 * the round header buttons are all made of. Unlike the Flutter version this
 * one really does blur — `backdrop-filter` is cheap in a browser, and the
 * effect is the whole reason the app's chrome picks up the colour of the map
 * behind it instead of sitting on top as an opaque white shape.
 */
export default function GlassSurface({
  children,
  tint = "light",
  className,
  style,
  as: Tag = "div",
}: {
  children?: ReactNode;
  tint?: GlassTint;
  className?: string;
  style?: CSSProperties;
  as?: "div" | "section" | "aside";
}) {
  return (
    <Tag
      className={[styles.glass, tint === "dark" ? styles.dark : styles.light, className ?? ""]
        .filter(Boolean)
        .join(" ")}
      style={style}
    >
      {children}
    </Tag>
  );
}
