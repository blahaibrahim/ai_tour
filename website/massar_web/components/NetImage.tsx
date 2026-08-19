"use client";

import { ImageOff } from "lucide-react";
import { useState } from "react";

import styles from "./NetImage.module.css";

/**
 * A remote photo with a shimmer while it loads and a quiet placeholder when it
 * fails or was never there.
 *
 * A plain `<img>`, not `next/image`. POI photos come from Wikimedia and
 * whatever else the ingestion pipeline found, so the host set is open-ended;
 * the optimiser would need every one of those domains declared in
 * `next.config.ts` and would 400 on the first host nobody thought of. The app
 * makes the same trade in `lib/widgets/net_image.dart`.
 */
export default function NetImage({
  url,
  alt,
  className,
  sizes,
}: {
  url: string | null | undefined;
  alt: string;
  className?: string;
  sizes?: string;
}) {
  const [state, setState] = useState<"loading" | "ready" | "failed">(url ? "loading" : "failed");

  return (
    <span className={[styles.frame, className ?? ""].filter(Boolean).join(" ")}>
      {state !== "failed" && url ? (
        // The hosts are open-ended, so `next/image` would 400 on the first one
        // nobody thought to declare in `next.config.ts` — see the note above.
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={url}
          alt={alt}
          sizes={sizes}
          loading="lazy"
          decoding="async"
          className={styles.img}
          data-ready={state === "ready" ? "true" : "false"}
          onLoad={() => setState("ready")}
          onError={() => setState("failed")}
        />
      ) : null}

      {state === "loading" ? <span className={styles.shimmer} aria-hidden /> : null}

      {state === "failed" ? (
        <span className={styles.fallback} aria-hidden>
          <ImageOff size={18} />
        </span>
      ) : null}
    </span>
  );
}
