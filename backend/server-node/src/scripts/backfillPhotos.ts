/**
 * Backfill `locations.photo_url` for rows ingested before the photo
 * fallback tiers existed.
 *
 * Fixing `ingestion/photos.ts` only affects POIs as they are ingested, and
 * `poi_tiles` keeps an already-fetched tile out of the pipeline until its
 * `expires_at` passes — so without this, existing rows keep their empty photo
 * for up to the full tile TTL.
 *
 * Only touches rows where `photo_url is null`; a row that already has a photo
 * is never overwritten. Dry-run by default.
 *
 *     npm run backfill:photos                       # report what would change
 *     npm run backfill:photos -- --apply
 *     npm run backfill:photos -- --apply --limit 20
 */
import { parseArgs } from "util";

import { sleep } from "../async";
import * as photos from "../ingestion/photos";
import { getAdminClient } from "../ingestion/supabaseAdmin";
import { unwrapRows } from "../supabase";
import { OsmTags } from "../types";

// The external APIs photos.ts calls are rate-limited; this runs as a batch
// job, so there is no reason to be anything other than polite.
const DELAY_S = 0.6;

/**
 * PostGIS returns geography as WKB hex; the payload after the 9-byte header is
 * (lng, lat) as little-endian doubles.
 */
function decodePoint(wkbHex: string): [number, number] {
  const raw = Buffer.from(wkbHex, "hex");
  const lng = raw.readDoubleLE(9);
  const lat = raw.readDoubleLE(17);
  return [lat, lng];
}

interface Row {
  id: string;
  geog: string;
  osm_tags: OsmTags | null;
  wikidata_qid: string | null;
  wikipedia_title: string | null;
  location_translations?: Array<{ name: string; locale: string }> | null;
}

function pad(text: string, width: number): string {
  return text.length >= width ? text.slice(0, width) : text + " ".repeat(width - text.length);
}

async function main(): Promise<number> {
  const { values } = parseArgs({
    options: {
      apply: { type: "boolean", default: false },
      limit: { type: "string" },
      place: { type: "string" },
    },
    allowPositionals: false,
  });
  const apply = values.apply === true;
  const limit = values.limit ? Number.parseInt(values.limit, 10) : null;
  const place = values.place ?? null;

  const client = getAdminClient();

  let query = client
    .from("locations")
    .select(
      "id,geog,osm_tags,wikidata_qid,wikipedia_title,location_translations(name,locale)",
    )
    .is("photo_url", null);
  if (limit) {
    query = query.limit(limit);
  }
  const rows = await unwrapRows<Row>(query);

  console.log(
    `${rows.length} location(s) without a photo` +
      `${apply ? "" : "  (dry run — pass --apply to write)"}\n`,
  );

  let resolved = 0;
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const translations = row.location_translations ?? [];
    const name =
      translations.find((t) => t.locale === "en")?.name ?? translations[0]?.name ?? null;
    const [lat, lng] = decodePoint(row.geog);
    const tags = row.osm_tags ?? {};

    const photo = await photos.resolvePhoto({
      wikipediaTitle: row.wikipedia_title,
      wikidataImageFilename: null,
      osmTags: tags,
      wikidataQid: row.wikidata_qid,
      name,
      lat,
      lng,
      placeContext: place ?? tags["addr:city"] ?? null,
    });

    const counter = String(i + 1).padStart(4);
    if (photo) {
      resolved += 1;
      console.log(
        `${counter}/${rows.length}  HIT  ${pad(name ?? row.id, 38)}  ` +
          `${pad(photo.photo_license, 16)}  ${photo.photo_url.slice(0, 60)}`,
      );
      if (apply) {
        await client
          .from("locations")
          .update({
            photo_url: photo.photo_url,
            photo_attribution: photo.photo_attribution,
            photo_license: photo.photo_license,
            photo_source_url: photo.photo_source_url,
          })
          .eq("id", row.id)
          .is("photo_url", null);
      }
    } else {
      console.log(`${counter}/${rows.length}   .   ${pad(name ?? row.id, 38)}`);
    }

    await sleep(DELAY_S * 1000);
  }

  if (rows.length === 0) {
    console.log("\nnothing to do");
    return 0;
  }
  console.log(
    `\nresolved ${resolved}/${rows.length} (${((100 * resolved) / rows.length).toFixed(1)}%)`,
  );
  if (resolved && !apply) {
    console.log("dry run — nothing written. Re-run with --apply to persist.");
  }
  return 0;
}

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);
