/**
 * Seed `pois` for a city from OpenStreetMap, instead of hand-authored fixtures.
 *
 *     npm run ingest:pois -- --city Algiers                    # dry run
 *     npm run ingest:pois -- --city Algiers --apply --publish
 *     npm run ingest:pois -- --city Algiers --apply --publish --retire-fixtures
 *
 * ## Why this exists
 *
 * The seeded catalogue came from the reference module's fixtures, whose own
 * docstring calls the durations "plausible, not measured" — and whose
 * coordinates turned out the same way. Several sit at three decimal places
 * (a ~110 m grid), one puts a mosque kilometres from where it stands, and two
 * different mosques carry the same English name. Those are not bugs to patch
 * row by row; they are what typed-in geodata looks like.
 *
 * OSM is surveyed. It also carries the things the fixtures had to invent:
 * names in en/fr/ar, the tags that say what a place *is*, its extent, and
 * links to Wikidata and Wikipedia — which is where `photos.ts` and
 * `describe.ts` pick the trail up afterwards.
 *
 * ## What this deliberately does not do
 *
 * It does not decide what is worth visiting on its own. `computeScore` ranks
 * candidates and `--min-score` cuts the tail, but scoring is a filter, not a
 * curator — which is why rows land as `draft` unless `--publish` is passed.
 * Only `published` POIs are eligible for a route (spec §10), so the review
 * step is a real gate rather than a formality.
 */
import { parseArgs } from "util";

import { sleep } from "../async";
import { fetchPois } from "../ingestion/overpass";
import { computeScore } from "../ingestion/scoring";
import { getAdminClient } from "../ingestion/supabaseAdmin";
import { fetchPageviews30d } from "../ingestion/wikipedia";
import { getCityConfigRepository } from "../routeGeneration/data/cityConfigRepository";
import { OsmTags } from "../types";

/**
 * OSM tags → the seven category keys in `categories`.
 *
 * Deliberately mapped from the raw tags rather than from
 * `categoryFromTags`'s display string: that function answers "what should we
 * call this to a reader", which is a different question with a much larger
 * vocabulary ("Aqueduct", "Cave", "Water park"). Anything this does not
 * recognise is dropped rather than filed under a nearest-guess — a mosque in
 * the museums list is worse than a mosque nobody sees.
 */
function categoryKeyFor(tags: OsmTags): string | null {
  const t = (k: string): string => String(tags[k] ?? "");

  if (t("tourism") === "museum") return "museum";
  if (t("tourism") === "viewpoint") return "viewpoint";
  if (t("tourism") === "gallery") return "cultural_venue";

  if (t("amenity") === "place_of_worship") return "religious_site";
  if (["mosque", "church", "cathedral", "synagogue", "chapel"].includes(t("building"))) {
    return "religious_site";
  }

  if (["park", "garden"].includes(t("leisure"))) return "park_garden";
  if (t("natural") === "beach" || t("leisure") === "beach_resort") return "beach";
  if (["peak", "cliff", "cape", "bay"].includes(t("natural"))) return "viewpoint";

  if (["theatre", "arts_centre", "cinema", "marketplace"].includes(t("amenity"))) {
    return "cultural_venue";
  }

  const historic = t("historic");
  if (
    [
      "monument", "memorial", "castle", "fort", "city_gate", "ruins",
      "archaeological_site", "tower", "aqueduct", "citywalls", "wall",
      "manor", "palace", "tomb",
    ].includes(historic)
  ) {
    return "historical_monument";
  }
  // `historic=building` / `historic=yes` say a place is old without saying
  // what it is. Kept, because in an Algerian medina that is most of the
  // heritage, and filed as a monument rather than guessed at.
  if (historic) return "historical_monument";

  return null;
}

/**
 * How long a visit takes, by category.
 *
 * OSM does not carry this — nothing does — so it is a judgement, and a
 * per-category default is a more honest one than a per-POI number typed from
 * nowhere. The fixtures gave the Casbah, a whole UNESCO quarter, forty-five
 * minutes and a single monument thirty; the shape of that is wrong before any
 * individual value is.
 *
 * Sites with a Wikidata id get a longer visit: it is a decent proxy for "this
 * is a destination rather than a thing you pass", and it is the only signal
 * available at ingest time.
 */
function dwellMinutes(categoryKey: string, notable: boolean): number {
  const base: Record<string, number> = {
    museum: 45,
    park_garden: 45,
    beach: 60,
    cultural_venue: 40,
    historical_monument: 25,
    religious_site: 25,
    viewpoint: 15,
  };
  const minutes = base[categoryKey] ?? 25;
  return notable ? Math.round(minutes * 1.4) : minutes;
}

/**
 * How close counts as arriving.
 *
 * Derived from the site's own extent where OSM gives one, because a
 * checkpoint radius is a property of the place, not of the app: standing at
 * the edge of the Jardin d'Essai is being there, and standing 40 m from a
 * statue is not. Bounded so a large park does not swallow its neighbours.
 */
function checkpointRadius(bounds: { minlat: number; minlon: number; maxlat: number; maxlon: number } | null): number {
  if (!bounds) return 30;
  const latSpanM = (bounds.maxlat - bounds.minlat) * 111_320;
  const lngSpanM =
    (bounds.maxlon - bounds.minlon) * 111_320 * Math.cos((bounds.minlat * Math.PI) / 180);
  const halfExtent = Math.max(latSpanM, lngSpanM) / 2;
  return Math.round(Math.min(90, Math.max(30, halfExtent)));
}

/** "en:Casbah of Algiers" → ["en", "Casbah of Algiers"]. */
function parseWikipediaTag(value: string | null | undefined): [string, string] | null {
  if (!value) return null;
  const at = value.indexOf(":");
  if (at <= 0) return null;
  return [value.slice(0, at), value.slice(at + 1)];
}

function pad(text: string, width: number): string {
  return text.length >= width ? text.slice(0, width - 1) + "…" : text.padEnd(width);
}

async function main(): Promise<number> {
  const { values } = parseArgs({
    options: {
      city: { type: "string" },
      "radius-km": { type: "string" },
      limit: { type: "string" },
      "min-score": { type: "string" },
      apply: { type: "boolean", default: false },
      publish: { type: "boolean", default: false },
      "retire-fixtures": { type: "boolean", default: false },
    },
    allowPositionals: false,
  });

  const cityName = values.city;
  if (!cityName) {
    console.log("--city is required, e.g. --city Algiers");
    return 1;
  }
  const radiusKm = Number.parseFloat(values["radius-km"] ?? "5");
  const limit = Number.parseInt(values.limit ?? "40", 10);
  const minScore = Number.parseFloat(values["min-score"] ?? "25");
  const apply = values.apply === true;
  const publish = values.publish === true;

  const cities = await getCityConfigRepository().listAll();
  const city = cities.find((c) => c.name.toLowerCase() === cityName.toLowerCase());
  if (!city) {
    console.log(`No city named "${cityName}". Have: ${cities.map((c) => c.name).join(", ")}`);
    return 1;
  }
  if (!city.centre) {
    console.log(`${city.name} has no centre — it needs a bounding_box before this can run.`);
    return 1;
  }

  // A square around the centre. Overpass takes a bbox, and a city's own
  // bounding_box here was derived from the fixtures this replaces, so it would
  // bound the search to exactly the area whose contents are in question.
  const dLat = radiusKm / 111.32;
  const dLng = radiusKm / (111.32 * Math.cos((city.centre.lat * Math.PI) / 180));
  const bbox = {
    latMin: city.centre.lat - dLat,
    latMax: city.centre.lat + dLat,
    lngMin: city.centre.lng - dLng,
    lngMax: city.centre.lng + dLng,
  };

  console.log(
    `${city.name} — ${radiusKm} km around ${city.centre.lat.toFixed(4)}, ` +
      `${city.centre.lng.toFixed(4)}${apply ? "" : "   (dry run — pass --apply to write)"}\n`,
  );

  const raw = await fetchPois(bbox.latMin, bbox.lngMin, bbox.latMax, bbox.lngMax);
  console.log(`Overpass returned ${raw.length} named, categorised candidates`);

  const client = getAdminClient();
  const categories =
    (await client.from("categories").select("id, key")).data ??
    ([] as Array<{ id: string; key: string }>);
  const categoryId = new Map(categories.map((c) => [c.key, c.id]));

  interface Candidate {
    name: string;
    nameEn: string | null;
    nameFr: string | null;
    nameAr: string | null;
    categoryKey: string;
    lat: number;
    lng: number;
    dwell: number;
    radius: number;
    openingHours: string | null;
    externalRef: string;
    score: number;
    breakdown: Record<string, number>;
  }

  const candidates: Candidate[] = [];

  for (const poi of raw) {
    const categoryKey = categoryKeyFor(poi.tags);
    if (!categoryKey || !categoryId.has(categoryKey)) continue;

    const wikipedia = parseWikipediaTag(poi.wikipedia ?? (poi.tags.wikipedia as string | undefined));
    let pageviews: number | null = null;
    if (wikipedia) {
      pageviews = await fetchPageviews30d(wikipedia[1], wikipedia[0]);
      // The pageviews API is per-article and rate limited; this loop is a
      // batch job, so it can afford to be polite.
      await sleep(120);
    }

    const [score, breakdown] = computeScore({
      category: poi.category,
      name: poi.name,
      osmTags: poi.tags,
      wikidataMatch: null,
      wikipediaFound: wikipedia !== null,
      pageviews30d: pageviews,
      hasPhoto: false,
    });

    if (score < minScore) continue;

    const notable = Boolean(poi.wikidata_qid ?? poi.tags.wikidata) || wikipedia !== null;
    candidates.push({
      name: poi.name,
      nameEn: (poi.tags["name:en"] as string) ?? poi.name,
      nameFr: (poi.tags["name:fr"] as string) ?? null,
      nameAr: (poi.tags["name:ar"] as string) ?? null,
      categoryKey,
      lat: poi.lat,
      lng: poi.lng,
      dwell: dwellMinutes(categoryKey, notable),
      radius: checkpointRadius(poi.bounds),
      openingHours: (poi.tags.opening_hours as string) ?? null,
      externalRef: `osm:${poi.osm_type}/${poi.osm_id}`,
      score,
      breakdown,
    });
  }

  candidates.sort((a, b) => b.score - a.score);
  const chosen = candidates.slice(0, limit);

  console.log(
    `${candidates.length} scored at or above ${minScore}; taking the top ${chosen.length}\n`,
  );
  console.log(`${pad("NAME", 42)}${pad("CATEGORY", 21)}${pad("SCORE", 7)}${pad("DWELL", 7)}RADIUS`);
  for (const c of chosen) {
    console.log(
      `${pad(c.nameEn ?? c.name, 42)}${pad(c.categoryKey, 21)}` +
        `${pad(c.score.toFixed(0), 7)}${pad(`${c.dwell}m`, 7)}${c.radius}m`,
    );
  }

  if (!apply) {
    console.log("\ndry run — nothing written. Re-run with --apply to persist.");
    return 0;
  }

  // Upsert on external_ref so re-running adopts the rows it wrote last time
  // rather than duplicating the city.
  const rows = chosen.map((c) => ({
    city_id: city.id,
    category_id: categoryId.get(c.categoryKey)!,
    name_en: c.nameEn,
    name_fr: c.nameFr,
    name_ar: c.nameAr,
    opening_hours_raw: c.openingHours,
    avg_visit_duration_minutes: c.dwell,
    checkpoint_radius_meters: c.radius,
    external_ref: c.externalRef,
    source: "api_seeded",
    status: publish ? "published" : "draft",
    // Kept, not discarded: without it the route selector has no way to rank
    // one candidate above another, and cannot fit a time budget.
    interest_score: c.score,
    score_breakdown: c.breakdown,
    lat: c.lat,
    lng: c.lng,
  }));

  const { error } = await client.rpc("upsert_ingested_pois", { p_rows: rows });
  if (error) {
    console.log(`\nwrite failed: ${error.message}`);
    return 1;
  }

  console.log(
    `\nwrote ${rows.length} POI(s) as ${publish ? "published" : "draft"}` +
      `${publish ? "" : " — pass --publish to make them routable"}`,
  );

  if (values["retire-fixtures"] === true) {
    // Soft delete, not a hard one: `route_stops` references these rows, so
    // routes already generated against them keep resolving. `pois_eligible`
    // filters on deleted_at, so they stop appearing in new ones.
    const { data: retired, error: retireError } = await client
      .from("pois")
      .update({ deleted_at: new Date().toISOString() })
      .eq("city_id", city.id)
      .like("external_ref", "fixture:%")
      .is("deleted_at", null)
      .select("id");
    if (retireError) {
      console.log(`retiring fixtures failed: ${retireError.message}`);
    } else {
      console.log(`retired ${retired?.length ?? 0} fixture POI(s) for ${city.name}`);
    }
  }

  console.log(
    "\nNext: npm run backfill:poi-photos -- --apply --city " + city.name,
  );
  return 0;
}

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);
