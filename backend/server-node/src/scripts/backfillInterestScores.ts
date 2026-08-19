/**
 * Resolve `pois.interest_score` / `pois.score_breakdown` for the seeded
 * catalogue, which was written by hand and has carried a null score since.
 *
 * A null score is not a cosmetic gap. `budgetFitter.valuePerMinute` falls back
 * to a flat `UNSCORED_VALUE` for it, so when *every* row is null the fallback
 * cancels out of the numerator and ranking collapses to `1 / dwell` — the
 * shortest visit wins, always. In Oran that put Fort Santa Cruz, the city's
 * best-known landmark, dead last at 75 minutes, and made the two beaches
 * unreachable by any prompt because they are the longest stops in the city.
 * Scores have to be real before ranking means anything.
 *
 * The sibling of `backfillPoiPhotos.ts`, and separate from `backfillPhotos.ts`
 * for the same reason: `locations` rows arrive from Overpass carrying
 * `osm_tags`, a `wikidata_qid` and a `wikipedia_title`, and
 * `ingestion/scoring.ts` keys off those. A `pois` row has a name, a
 * coordinate, a category and a photo. So this rebuilds the scorer's inputs
 * from what a seeded row does have — see `discover` and `osmTagsForCategory`
 * — rather than teaching the scorer a second input shape. The weights, the
 * breakdown format and the explainability guarantee stay exactly as ingestion
 * produces them.
 *
 * Only touches rows where `interest_score is null` unless `--force`. Dry-run
 * by default.
 *
 *     npm run backfill:scores                        # report what would change
 *     npm run backfill:scores -- --apply
 *     npm run backfill:scores -- --apply --city Oran
 *     npm run backfill:scores -- --apply --force     # rescore everything
 */
import { parseArgs } from "util";

import { sleep } from "../async";
import { haversineKm } from "../data/geo";
import { computeScore, ScoreBreakdown } from "../ingestion/scoring";
import { getAdminClient } from "../ingestion/supabaseAdmin";
import { fetchWikidataItems } from "../ingestion/wikidata";
import { fetchPageviews30d, fetchSummary } from "../ingestion/wikipedia";
import { getCityConfigRepository } from "../routeGeneration/data/cityConfigRepository";
import { getPoiRepository } from "../routeGeneration/data/poiRepository";
import { Poi } from "../routeGeneration/types";
import { normalizeFold } from "../text";
import { OsmTags, WikidataItem } from "../types";

/** Wikidata SPARQL and the Wikimedia REST APIs are shared infrastructure and
 * this is a batch job — the same courtesy delay the other backfills use. */
const DELAY_S = 1.0;

/** Search radius for Wikidata items around a seeded coordinate. Wide enough to
 * cover a hand-placed pin sitting at a site's entrance rather than its
 * centroid, narrow enough that a dense old town does not return the whole
 * quarter. Name matching, not this radius, is what decides the pairing. */
const SEARCH_RADIUS_KM = 0.6;

/**
 * Why there is no proximity-only fallback here, unlike `wikidata.matchNearest`.
 *
 * That function pairs on distance alone within 75 m, which is sound for the
 * OSM coordinates it was written for: they come from the same survey as the
 * Wikidata item and are precise to the building. A seeded coordinate is a pin
 * someone dropped by eye, so 75 m is not the tight bound it looks like — the
 * first dry run of this script paired Oran Regional Theatre with the *city of
 * Oran* and the Palace of the Bey with the Museum of Modern Art, inheriting
 * both subjects' sitelinks and heritage status. Wrong provenance is worse than
 * no provenance: a missing match costs a POI some points, a wrong one hands it
 * someone else's fame and there is nothing in the breakdown to show it.
 *
 * So the name has to agree, and distance only decides between candidates that
 * already do.
 */

/**
 * The tags this POI would carry if it had come through Overpass instead of
 * being typed in by hand.
 *
 * Only the two tag facts `computeScore` actually reads are reconstructed:
 * `natural_or_historic_baseline` (+15, for `natural` / `historic` / a park)
 * and `osm_tag_richness` (up to +8, from `website` / `opening_hours` /
 * `description` / `image`). This is not inventing a signal — a beach in OSM is
 * `natural=beach` and a monument is `historic=monument`, so a seeded beach
 * scoring as if it were untagged is the artefact, not this.
 *
 * Museums, religious sites and cultural venues get no baseline tag, which is
 * also what OSM would give them: they are `tourism=museum` / `amenity=*`, and
 * `computeScore` deliberately does not extend the natural-or-historic baseline
 * to those. They earn their score from Wikipedia and heritage instead.
 */
function osmTagsForCategory(poi: Poi): OsmTags {
  const tags: Record<string, string> = {};

  switch (poi.categoryKey) {
    case "beach":
      tags.natural = "beach";
      break;
    case "viewpoint":
      // Both seeded viewpoints are hills (Murdjadjo, Djebel Santon); OSM maps
      // the landform, and it is the landform that makes them worth the climb.
      tags.natural = "peak";
      break;
    case "park_garden":
      tags.leisure = "park";
      break;
    case "historical_monument":
      tags.historic = "monument";
      break;
    default:
      break;
  }

  if (poi.openingHoursRaw) tags.opening_hours = poi.openingHoursRaw;
  if (poi.descriptionEn) tags.description = poi.descriptionEn;
  if (poi.photoUrl) tags.image = poi.photoUrl;

  return tags as OsmTags;
}

/** Every name a seeded row knows itself by. The English label is what Wikidata
 * returns, but "Djamaa el Djazaïr" is indexed under its French and Arabic
 * forms far more often than its English one. */
function nameVariants(poi: Poi): string[] {
  return [poi.nameEn, poi.nameFr, poi.nameAr].filter((n): n is string => Boolean(n));
}

const STOPWORDS = new Set([
  "the", "of", "de", "du", "des", "la", "le", "les", "el", "al", "and", "et",
  "d", "l", "a", "in", "at",
]);

/** Content words, accent- and case-folded. `normalizeFold` already strips
 * diacritics, so "Djamaa el Djazaïr" and "Djamaa el Djazair" agree here. */
function contentTokens(name: string): Set<string> {
  return new Set(
    normalizeFold(name)
      .split(/[^\p{L}\p{N}]+/u)
      .filter((token) => token.length > 1 && !STOPWORDS.has(token)),
  );
}

/**
 * Whether two names are the same place.
 *
 * Every content word of the shorter name has to appear in the longer one.
 * That accepts "Fort Santa Cruz" ~ "Santa Cruz Fort (Oran)" while rejecting
 * "Pasha Mosque" ~ "Great Mosque", which share only the near-generic "mosque".
 * Subset rather than a similarity ratio because the two names differ by
 * *qualifiers* far more often than by spelling, and a ratio has to be tuned
 * against name length while a subset does not.
 *
 * A one-word name has to match exactly instead. Subset matching is only a safe
 * relaxation when the shorter name still carries enough words to identify the
 * subject on its own, and one does not: it made the Gambetta quarter match
 * "Mosquée Abdelhamid Benbadiss Gambetta in Oran" — a mosque *inside* it, with
 * its own article and its own pageviews. Everything a single token can match
 * loosely, it can match wrongly.
 */
function namesAgree(a: string, b: string): boolean {
  const left = contentTokens(a);
  const right = contentTokens(b);
  if (left.size === 0 || right.size === 0) return false;
  const [shorter, longer] = left.size <= right.size ? [left, right] : [right, left];
  if (shorter.size === 1) return longer.size === 1 && [...shorter][0] === [...longer][0];
  for (const token of shorter) {
    if (!longer.has(token)) return false;
  }
  return true;
}

/**
 * Whether an article found by guessing a title is actually about a place in
 * this city.
 *
 * Only the guessed path needs this. A title Wikidata handed over is already
 * anchored: the item was selected by coordinate *and* name, so the article
 * behind it is about something standing where the POI stands. A guessed title
 * has neither anchor, and English Wikipedia resolves a bare place name to
 * whatever is most famous under it — "Gambetta", Oran's quarter, comes back as
 * Léon Gambetta the French statesman, complete with a politician's pageviews
 * feeding a POI's popularity score.
 *
 * The city or the country appearing in the opening paragraph is a weak test
 * and deliberately so: it is not trying to verify the subject, only to reject
 * an article that is plainly about somewhere else.
 */
function mentionsPlace(extract: string, cityName: string): boolean {
  const haystack = normalizeFold(extract);
  return [cityName, "algeria", "algerie", "algerian"].some((needle) =>
    haystack.includes(normalizeFold(needle)),
  );
}

interface Discovery {
  wikidata: WikidataItem | null;
  wikipediaTitle: string | null;
  pageviews30d: number | null;
  /** How the Wikipedia article was found, for the report — a title guessed
   * from the POI's own name is a weaker pairing than one Wikidata handed us,
   * and the operator reviewing a dry run should be able to see which is which. */
  via: "wikidata" | "name" | null;
}

/**
 * Rebuilds the knowledge-base inputs `computeScore` expects, from a name and a
 * coordinate.
 *
 * Wikidata first: a hit brings heritage status, sitelink count and usually the
 * Wikipedia title in one round trip. When it misses, the POI's own names are
 * tried as article titles directly — seeded rows are real, well-known places
 * with real names, so this recovers the +20 article and the pageview signal
 * for the ones Wikidata has no coordinate for. A guessed title is only kept if
 * the article exists, its own title still agrees with the POI's name after the
 * endpoint has resolved redirects, and the article is about somewhere in this
 * city — see `mentionsPlace`.
 */
async function discover(poi: Poi, cityName: string): Promise<Discovery> {
  const variants = nameVariants(poi);

  const items = await fetchWikidataItems(
    poi.location.lat,
    poi.location.lng,
    SEARCH_RADIUS_KM,
  );

  let matched: WikidataItem | null = null;
  let bestDistanceKm = Number.POSITIVE_INFINITY;
  for (const item of items) {
    if (item.lat === null || item.lng === null) continue;
    if (!variants.some((name) => namesAgree(name, item.name))) continue;
    // Among items that all agree on the name, the nearest is the one.
    const distanceKm = haversineKm(poi.location.lat, poi.location.lng, item.lat, item.lng);
    if (distanceKm < bestDistanceKm) {
      matched = item;
      bestDistanceKm = distanceKm;
    }
  }

  let wikipediaTitle = matched?.wikipedia_title ?? null;
  let via: Discovery["via"] = wikipediaTitle ? "wikidata" : null;

  if (!wikipediaTitle) {
    for (const name of variants) {
      await sleep(DELAY_S * 1000);
      const summary = await fetchSummary(name);
      if (summary && namesAgree(name, summary.title) && mentionsPlace(summary.extract, cityName)) {
        wikipediaTitle = summary.title;
        via = "name";
        break;
      }
    }
  }

  let pageviews30d: number | null = null;
  if (wikipediaTitle) {
    await sleep(DELAY_S * 1000);
    pageviews30d = await fetchPageviews30d(wikipediaTitle);
  }

  return { wikidata: matched, wikipediaTitle, pageviews30d, via };
}

function pad(text: string, width: number): string {
  return text.length >= width ? text.slice(0, width) : text + " ".repeat(width - text.length);
}

/** The breakdown's own keys, so a dry run shows *why* a score came out where
 * it did without needing the JSON. */
function summarize(breakdown: ScoreBreakdown): string {
  return Object.entries(breakdown)
    .sort((a, b) => b[1] - a[1])
    .map(([key, value]) => `${key}:${value}`)
    .join(" ");
}

async function main(): Promise<number> {
  const { values } = parseArgs({
    options: {
      apply: { type: "boolean", default: false },
      force: { type: "boolean", default: false },
      limit: { type: "string" },
      city: { type: "string" },
    },
    allowPositionals: false,
  });
  const apply = values.apply === true;
  const force = values.force === true;
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
  let scored = 0;

  for (const city of cities) {
    // Through the repository rather than a raw query: it is the thing that
    // already knows how to get coordinates out of a geography column over
    // PostgREST.
    const pois = (await getPoiRepository().findAllPublished(city.id)).filter(
      (p) => force || p.interestScore === null,
    );
    const batch = limit ? pois.slice(0, Math.max(0, limit - total)) : pois;

    console.log(
      `\n${city.name}: ${pois.length} POI(s) ${force ? "to rescore" : "without a score"}` +
        `${batch.length < pois.length ? ` (taking ${batch.length})` : ""}` +
        `${apply ? "" : "  (dry run — pass --apply to write)"}`,
    );

    for (const poi of batch) {
      total += 1;
      const name = poi.nameEn ?? poi.nameFr ?? poi.nameAr ?? poi.id;

      const found = await discover(poi, city.name);
      const [score, breakdown] = computeScore({
        category: poi.categoryKey,
        name,
        osmTags: osmTagsForCategory(poi),
        wikidataMatch: found.wikidata,
        wikipediaFound: found.wikipediaTitle !== null,
        pageviews30d: found.pageviews30d,
        hasPhoto: Boolean(poi.photoUrl),
      });

      const counter = String(total).padStart(4);
      const perMinute = (score / Math.max(1, poi.avgVisitDurationMinutes)).toFixed(2);
      // The pairing is shown, not just the score: attaching the wrong
      // subject's heritage status is the failure mode that leaves no trace in
      // the breakdown, and a dry run is where it gets caught.
      const pairing = [
        found.wikidata ? `wd:${found.wikidata.name}` : null,
        found.wikipediaTitle ? `wp(${found.via}):${found.wikipediaTitle}` : null,
      ]
        .filter(Boolean)
        .join(" ");
      console.log(
        `${counter}  ${String(score).padStart(5)}  ${pad(perMinute, 6)}/min  ` +
          `${pad(name, 30)}  ${pad(pairing || "-", 52)}  ${summarize(breakdown)}`,
      );

      if (score !== 0) scored += 1;

      if (apply) {
        let update = client
          .from("pois")
          .update({ interest_score: score, score_breakdown: breakdown })
          .eq("id", poi.id);
        // Re-checked at write time so a concurrent run cannot overwrite a
        // score the other one just resolved. `--force` is the explicit
        // instruction to overwrite, so it skips the guard.
        if (!force) update = update.is("interest_score", null);
        const { error } = await update;
        if (error) console.log(`      write failed: ${error.message}`);
      }

      await sleep(DELAY_S * 1000);
    }
  }

  if (total === 0) {
    console.log("\nnothing to do");
    return 0;
  }

  console.log(`\nscored ${scored}/${total}`);
  if (!apply) {
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
