/**
 * Resolve `pois.photo_*` for route-generation POIs that have no photo yet.
 *
 * The sibling of `backfillPhotos.ts`, which does the same job for the
 * `locations` catalogue. A separate script rather than a flag on that one
 * because the two tables have genuinely different inputs: `locations` rows
 * arrive from Overpass carrying `osm_tags`, a `wikidata_qid` and a
 * `wikipedia_title`, and every structured tier in `ingestion/photos.ts` keys
 * off those. `pois` rows have none of them — the seeded catalogue is
 * hand-authored — so only the geographic discovery tiers can run.
 *
 * That is not a downgrade. Those tiers are the ones `photos.ts` was extended
 * for precisely because 132 of 134 unphotographed locations had no knowledge-
 * base id either, and they work off exactly what a `pois` row does have: a
 * name, its French and Arabic variants, and a coordinate.
 *
 * Only touches rows where `photo_url is null`; a row that already has a photo
 * is never overwritten. Dry-run by default.
 *
 *     npm run backfill:poi-photos                    # report what would change
 *     npm run backfill:poi-photos -- --apply
 *     npm run backfill:poi-photos -- --apply --city Algiers
 */
import { parseArgs } from "util";

import { sleep } from "../async";
import * as photos from "../ingestion/photos";
import { getAdminClient } from "../ingestion/supabaseAdmin";
import { getCityConfigRepository } from "../routeGeneration/data/cityConfigRepository";
import { getPoiRepository } from "../routeGeneration/data/poiRepository";
import { OsmTags } from "../types";

// The external APIs photos.ts calls are rate-limited; this runs as a batch
// job, so there is no reason to be anything other than polite.
const DELAY_S = 0.6;

function pad(text: string, width: number): string {
  return text.length >= width ? text.slice(0, width) : text + " ".repeat(width - text.length);
}

/**
 * Presents a POI's multilingual names the way `photos.ts` already knows how to
 * read them.
 *
 * `nameVariants` collects `name`, `name:*` and the alt-name tags off an OSM
 * tag bag, and the module's own notes explain why that matters here: Commons
 * filenames for Algerian subjects are routinely French or Arabic — "Mosquée du
 * Dey (Alger)", "تمثال الامير عبد القادر" — while the display name is English.
 * A `pois` row has those variants in columns instead of tags, so this hands
 * them over in the shape the matcher expects rather than teaching the matcher
 * a second shape.
 */
function namesAsOsmTags(poi: {
  nameEn: string | null;
  nameFr: string | null;
  nameAr: string | null;
}): OsmTags {
  const tags: Record<string, string> = {};
  if (poi.nameEn) {
    tags.name = poi.nameEn;
    tags["name:en"] = poi.nameEn;
  }
  if (poi.nameFr) tags["name:fr"] = poi.nameFr;
  if (poi.nameAr) tags["name:ar"] = poi.nameAr;
  return tags as OsmTags;
}

async function main(): Promise<number> {
  const { values } = parseArgs({
    options: {
      apply: { type: "boolean", default: false },
      limit: { type: "string" },
      city: { type: "string" },
    },
    allowPositionals: false,
  });
  const apply = values.apply === true;
  const limit = values.limit ? Number.parseInt(values.limit, 10) : null;
  const cityFilter = values.city?.toLowerCase() ?? null;

  const client = getAdminClient();

  const cities = (await getCityConfigRepository().listAll()).filter(
    (c) => cityFilter === null || c.name.toLowerCase() === cityFilter,
  );
  if (cities.length === 0) {
    console.log(cityFilter ? `no city named "${values.city}"` : "no cities in the catalogue");
    return 1;
  }

  let total = 0;
  let resolved = 0;

  for (const city of cities) {
    // Read through the module's own repository rather than a raw query: it is
    // the thing that already knows how to get coordinates out of a geography
    // column over PostgREST.
    const pois = (await getPoiRepository().findAllPublished(city.id)).filter(
      (p) => !p.photoUrl,
    );
    const batch = limit ? pois.slice(0, Math.max(0, limit - total)) : pois;

    console.log(
      `\n${city.name}: ${pois.length} POI(s) without a photo` +
        `${batch.length < pois.length ? ` (taking ${batch.length})` : ""}` +
        `${apply ? "" : "  (dry run — pass --apply to write)"}`,
    );

    for (const poi of batch) {
      total += 1;
      const name = poi.nameEn ?? poi.nameFr ?? poi.nameAr;

      const photo = await photos.resolvePhoto({
        // No knowledge-base ids on a seeded row — the discovery tiers are the
        // whole of what runs here.
        wikipediaTitle: null,
        wikidataImageFilename: null,
        wikidataQid: null,
        osmTags: namesAsOsmTags(poi),
        name,
        lat: poi.location.lat,
        lng: poi.location.lng,
        // Stops the city's own name counting as a subject match — the
        // "Museum of Modern Art of Algiers" matching "Streets in Algiers
        // 2024 06.jpg" on the token "algiers" false positive.
        placeContext: city.name,
      });

      const counter = String(total).padStart(4);
      if (photo) {
        resolved += 1;
        console.log(
          `${counter}  HIT  ${pad(name ?? poi.id, 40)}  ` +
            `${pad(photo.photo_license, 16)}  ${photo.photo_url.slice(0, 58)}`,
        );
        if (apply) {
          const { error } = await client
            .from("pois")
            .update({
              photo_url: photo.photo_url,
              photo_attribution: photo.photo_attribution,
              photo_license: photo.photo_license,
              photo_source_url: photo.photo_source_url,
            })
            .eq("id", poi.id)
            // Re-checked at write time so a concurrent run cannot overwrite a
            // photo the other one just resolved.
            .is("photo_url", null);
          if (error) console.log(`      write failed: ${error.message}`);
        }
      } else {
        console.log(`${counter}   .   ${pad(name ?? poi.id, 40)}`);
      }

      await sleep(DELAY_S * 1000);
    }
  }

  if (total === 0) {
    console.log("\nnothing to do");
    return 0;
  }

  console.log(`\nresolved ${resolved}/${total} (${((100 * resolved) / total).toFixed(1)}%)`);
  if (!apply && resolved > 0) {
    console.log("dry run — nothing written. Re-run with --apply to persist.");
  }
  // A miss is not a failure: some POIs genuinely have no free-licensed
  // photograph, and the app draws its own placeholder for those rather than
  // borrowing a picture of somewhere else.
  return 0;
}

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);
