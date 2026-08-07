/**
 * Photo resolution — replaces the `picsum.photos` placeholders in
 * `lib/models/location.dart` with real, licensed photos of the actual place.
 *
 * ## Approaches evaluated
 *
 * Tested empirically against real ingestion candidates before writing, not
 * assumed from documentation. The original four:
 *
 * 1. **Wikipedia REST summary thumbnail** (`wikipedia.fetchSummary`) — tested
 *    against the Casbah and Timgad, returned a correct, appropriately-sized
 *    thumbnail plus its full-resolution original for both, in the same call
 *    that already fetches the blurb text. Reliable, free, no extra request.
 * 2. **Wikidata P18** — the per-tile SPARQL query already returns this
 *    alongside heritage status, so it's nearly free when present. Weaker
 *    coverage than (1): not every Wikidata item carries a P18 claim even when
 *    its corresponding Wikipedia article has a lead image.
 * 3. **Wikipedia full-text search**, as a fallback for POIs with no direct
 *    Wikidata/Wikipedia link — tested with `srsearch=Aqueduc Romain
 *    Constantine Algeria`. Top (only) hit was "History of the Loiret", a
 *    French department article with zero relevance. Rejected *in that form*.
 * 4. **Search-engine image discovery**, both general and Commons-restricted —
 *    general search returned exclusively paid stock-photo licensors (Alamy,
 *    Dreamstime, Shutterstock), unusable without per-image licensing and
 *    hotlink-blocked besides. Restricting to `commons.wikimedia.org` looked
 *    promising — top result literally titled "File:Aqueduc romain.JPG" — but
 *    that file depicts a bridge in Carrazeda de Ansiães, **Portugal**. A
 *    silent false positive from a match that looked strong. Rejected *in that
 *    form*.
 *
 * ## Why tiers 1–4 alone left two thirds of the catalogue with no photo
 *
 * Measured against the live catalogue: 134 of 203 locations had no photo, and
 * **132 of those 134 had neither a `wikidata_qid` nor a `wikipedia_title`**.
 * Every structured tier is inapplicable by construction for that long tail —
 * it isn't that they were failing, it's that they never ran. Conversely, of
 * the rows that *did* carry a `wikipedia_title`, zero lacked a photo: tier 1
 * is ~100% effective whenever it applies.
 *
 * So the gap is entirely POIs that OSM never linked to a knowledge base. Some
 * are genuinely unphotographed (an escape room, private embassy grounds, a
 * node literally named "Ne"); but the misses also included Ketchaoua Mosque,
 * the Casbah of Algiers, and the Museum of Modern Art — all extensively
 * photographed on Commons, just not reachable without an ID.
 *
 * ## What closes the gap: anchor on coordinates, then verify by name
 *
 * The failure mode that sank approaches 3–4 was matching on *text similarity
 * alone*, which cannot distinguish an Algerian aqueduct from a Portuguese
 * one. Both new signals below constrain the search geographically first —
 * Commons and Wikipedia both expose `list=geosearch`, which returns only
 * items geotagged within a radius of a coordinate — so a Portugal/Algeria
 * mixup is not representable.
 *
 * Geography alone is not sufficient either, and this was measured rather than
 * assumed. Accepting the *nearest* geotagged Commons file within 60m produced
 * 15 matches, and inspection showed them to be mostly wrong subjects: the
 * well "Bir Jebah" got `Ourida Meddad.jpg` (a portrait of a person), "Beb El
 * Bhar" got `Voiture ancienne alger.jpg` (an old car), "Kilometre Zero" got a
 * map of Algiers' municipalities. Photos taken *near* a POI are routinely not
 * photos *of* it. Proximity-only acceptance is therefore rejected outright.
 *
 * The rule that works is the conjunction: **within the radius AND sharing a
 * distinctive name token**. Name matching runs over every name variant OSM
 * carries (`name`, `name:en`, `name:fr`, `name:ar`, `alt_name`, …) because
 * Commons filenames for these subjects are frequently French or Arabic
 * ("Mosquée du Dey (Alger)", "تمثال الامير عبد القادر") while the POI's
 * display name is English. Tokens naming the containing city are excluded
 * from counting as a match — "Museum of Modern Art of Algiers" matching
 * `Streets in Algiers 2024 06.jpg` on the token "algiers" alone is exactly
 * the false positive this guard exists to stop.
 *
 * ## Openverse, in place of scraping a search engine
 *
 * The remaining tier is an image search engine, but a licensed one: Openverse
 * (the Creative Commons / WordPress index over Commons, Flickr, and others).
 * It is used instead of scraping DuckDuckGo/Qwant/Yahoo results — those were
 * tried and are both bot-blocked (403) and, more fundamentally, return images
 * with no license metadata, which this module may not store (see
 * `commons.resolveCommonsFile`'s note). Openverse returns `creator`,
 * `license`, `license_version` and `foreign_landing_url` per result, so the
 * "never store a photo_url without knowing what it's licensed under" rule
 * still holds.
 *
 * Openverse is matched on name tokens under the same guard, because
 * unguarded it is exactly as credulous as any other text search: querying it
 * for "Palace of the Dey" returns the Doge's Palace in **Venice** as the top
 * hit, and "Embassy of France" returns the French embassy in **Armenia**.
 *
 * Below every tier, this module still returns `null`; the app already has a
 * placeholder treatment for that case, and a wrong photo is worse than none.
 */
import { sleep } from "../async";
import { parseJson, QueryParams, raiseForStatus, request } from "../http";
import { getLogger } from "../logger";
import { intersects, isSubsetOf, normalizeFold, unionInto, unquote, words } from "../text";
import { OsmTags, PhotoFields, WikipediaSummary } from "../types";
import { resolveCommonsFile } from "./commons";
import { fetchSummary } from "./wikipedia";

const logger = getLogger("ingestion.photos");

export const TIMEOUT_S = 15;

/**
 * The pure matching rules, exposed for the regression and Python-parity
 * harnesses. The Python equivalents are `_`-prefixed and imported directly by
 * `test_poi_rules.py`; bundling them here keeps that possible without widening
 * this module's working surface, which is just `resolvePhoto` and
 * `resolveNearbyPhoto`.
 */
export const internals = {
  tokens: (text: string, extraStop?: ReadonlySet<string>) => tokens(text, extraStop),
  matchesSubject: (c: string, vt: Array<Set<string>>, ps: ReadonlySet<string>) =>
    matchesSubject(c, vt, ps),
  placeStopwords: (tags: OsmTags, place: string | null) => placeStopwords(tags, place),
  nameVariants: (name: string | null, tags: OsmTags) => nameVariants(name, tags),
  isTagDump: (text: string) => isTagDump(text),
  mentionsPlace: (c: string, ps: ReadonlySet<string>) => mentionsPlace(c, ps),
  looksLikeAPhotograph: (f: string) => looksLikeAPhotograph(f),
  commonsFromUrl: (u: string) => commonsFromUrl(u),
};

const RETRY_AFTER_FALLBACK_S = 2.0;
const MAX_RETRY_WAIT_S = 10.0;

// Radii for the coordinate-anchored tiers. Deliberately generous for Commons
// files (a photographer standing back from a large building geotags where the
// camera was, not the subject) and tighter for Wikidata, where the coordinate
// is the subject's own and a mismatch means it's a different subject.
export const COMMONS_GEO_RADIUS_M = 400;
export const WIKIPEDIA_GEO_RADIUS_M = 400;
export const WIKIDATA_VERIFY_RADIUS_M = 250;

// Words that carry no subject information, so a match on them alone is not
// evidence the image depicts this POI. Covers the EN/FR/AR generics that
// dominate this catalogue's names.
const GENERIC_TOKENS = new Set([
  "the", "of", "de", "la", "le", "les", "du", "des", "el", "al", "and",
  "et", "in", "at", "sur", "ex", "site", "center", "centre", "parc",
  "park", "jardin", "garden", "plage", "beach", "musee", "museum",
  "statue", "place", "cite", "villa", "ancien", "ancienne", "old", "new",
  "grand", "grande", "petit", "petite", "public", "national", "unesco",
  "world", "heritage", "former", "location", "complexe", "hotel", "photo",
  "file", "image", "view", "vue",
  "حديقة", "شاطئ", "متحف", "قصر", "مسجد", "ساحة", "تمثال", "مقام", "دار",
  "باب", "بئر", "صورة",
]);

const ARABIC_RANGE: [string, string] = ["؀", "ۿ"];

// Streets are routinely named after the landmark they run past, so a caption
// naming a thoroughfare describes the street, not the landmark. Measured: the
// city gate "Bab Azzoun" matched `Publicité pour la marque de soda Crush en
// mosaïque, rue Bab Azzoun à Alger` — a photo of a soda advert — on a full
// name match, because the street carries the gate's name.
const THOROUGHFARE_TOKENS = new Set([
  "rue", "street", "avenue", "boulevard", "route", "chemin", "impasse",
  "ruelle", "شارع", "نهج", "طريق", "زنقة",
]);

/**
 * GET returning parsed JSON, or null on any failure.
 *
 * Retries once on 429/503 honouring `Retry-After`. Wikimedia rate-limits
 * a burst of geosearch calls, and the previous code's blanket
 * catch-everything turned that into a silent "no photo found" —
 * indistinguishable from a genuine miss, which is how a throttled run can
 * look like a broken one.
 */
async function getJsonOrNull<T>(
  url: string,
  params: QueryParams,
  what: string,
): Promise<T | null> {
  for (const attempt of [0, 1]) {
    try {
      const response = await request(url, { params, timeoutMs: TIMEOUT_S * 1000 });
      if ((response.status === 429 || response.status === 503) && attempt === 0) {
        const retryAfter = Number.parseFloat(response.headers.get("Retry-After") ?? "");
        const delay = Number.isFinite(retryAfter) ? retryAfter : RETRY_AFTER_FALLBACK_S;
        logger.info(`${what} throttled (${response.status}), retrying in ${delay.toFixed(1)}s`);
        await sleep(Math.min(delay, MAX_RETRY_WAIT_S) * 1000);
        continue;
      }
      await raiseForStatus(response, url);
      return await parseJson<T>(response, url);
    } catch (error) {
      logger.warning(`${what} failed: ${error instanceof Error ? error.message : error}`);
      return null;
    }
  }
  return null;
}

/**
 * Unused by the current token rule, which keeps every word at 3+ characters
 * regardless of script. Kept because it is the discriminator the rule's
 * docstring describes wanting (Arabic roots are short; Latin noise words are
 * short too), and removing it would erase that intent.
 */
function hasArabic(word: string): boolean {
  return Array.from(word).some((c) => c >= ARABIC_RANGE[0] && c <= ARABIC_RANGE[1]);
}
void hasArabic;

/**
 * Distinctive tokens only — generics, caller-supplied place words, and short
 * fragments are dropped.
 */
function tokens(text: string, extraStop: ReadonlySet<string> = new Set()): Set<string> {
  const out = new Set<string>();
  for (const word of words(normalizeFold(text))) {
    if (GENERIC_TOKENS.has(word) || extraStop.has(word)) continue;
    if (word.length < 3) continue;
    out.add(word);
  }
  return out;
}

/**
 * Every name OSM knows this POI by. Commons filenames for these subjects are
 * as often French or Arabic as English, so matching only on the display name
 * throws away most of the available signal.
 */
function nameVariants(name: string | null | undefined, osmTags: OsmTags): string[] {
  const variants: string[] = [];
  if (name) variants.push(name);
  for (const [key, value] of Object.entries(osmTags ?? {})) {
    if (!value || typeof value !== "string") continue;
    if (
      key === "name" ||
      key.startsWith("name:") ||
      ["alt_name", "official_name", "short_name", "int_name"].includes(key)
    ) {
      variants.push(value);
    }
  }
  // Dedupe, preserving order so the display name stays the primary query.
  const seen = new Set<string>();
  return variants.filter((v) => (seen.has(v) ? false : (seen.add(v), true)));
}

/**
 * Tokens naming the containing city/region, which must not count as a subject
 * match on their own (the "Streets in Algiers" false positive).
 */
function placeStopwords(osmTags: OsmTags, placeContext: string | null | undefined): Set<string> {
  const parts: string[] = [placeContext ?? ""];
  for (const key of ["addr:city", "addr:province", "addr:state", "addr:country", "is_in"]) {
    const value = (osmTags ?? {})[key];
    if (typeof value === "string") parts.push(value);
  }
  const stop = new Set<string>();
  for (const part of parts) {
    unionInto(
      stop,
      words(normalizeFold(part)).filter((w) => w.length >= 3),
    );
  }
  return stop;
}

/**
 * True when the candidate text contains *every* distinctive token of at least
 * one of the POI's name variants.
 *
 * Requiring full coverage of a variant rather than any single shared token
 * is what separates a real match from a coincidence, and this was measured:
 * the any-token rule accepted `Mausolée de Sidi Abderrahmane ben Mohamed
 * ben Makhlouf` for "Sidi Mohamed Sharif Mosque" (overlapping on the
 * honorific "sidi" and the given name "mohamed" — two tokens, still the
 * wrong building) and `Streets in Algiers 2024 06.jpg` for "Museum of
 * Modern Art of Algiers". Under full coverage both are rejected, because
 * "sharif" and "modern" are absent, while "Ketchaoua Mosque architecture –
 * Algiers 8.jpg" still matches "Ketchaoua Mosque" exactly.
 */
function matchesSubject(
  candidate: string,
  variantTokens: Array<Set<string>>,
  placeStop: ReadonlySet<string>,
): boolean {
  const candidateTokens = tokens(candidate, placeStop);
  if (candidateTokens.size === 0) return false;
  if (!variantTokens.some((t) => t.size > 0 && isSubsetOf(t, candidateTokens))) return false;

  // A caption naming a street is about the street. Only reject when the POI
  // itself isn't a thoroughfare, so an actual named street still matches.
  const candidateWords = new Set(words(normalizeFold(candidate)));
  if (intersects(candidateWords, THOROUGHFARE_TOKENS)) {
    const ownWords = new Set<string>();
    for (const t of variantTokens) unionInto(ownWords, t);
    if (!intersects(ownWords, THOROUGHFARE_TOKENS)) return false;
  }
  return true;
}

/**
 * Whether a title is a bag of hashtags rather than a caption.
 *
 * These defeat name matching by brute force: a title carrying twenty tags
 * will contain almost any name's tokens by coincidence. Measured — the
 * Flickr title `#algiers #alger #algeria #casbah #oldcity
 * #darmustaphapacha ... #palais #palace #dey` fully covers "Palace of the
 * Dey" and names the city, passing every other guard, while actually
 * depicting Dar Mustapha Pacha, a different building entirely.
 */
function isTagDump(text: string): boolean {
  return (text.match(/#/g) ?? []).length >= 5;
}

/**
 * Whether the candidate names the POI's city/region.
 *
 * Required only by the Openverse tier, which is the one tier with no
 * geographic anchor of its own. Full name coverage is not sufficient
 * there because a candidate can contain the whole name and still add a
 * qualifier that moves it elsewhere: "Embassy of France in Armenia"
 * contains every token of "Embassy of France". Demanding the place name
 * substitutes for the coordinate filter the other tiers get for free.
 */
function mentionsPlace(candidate: string, placeStop: ReadonlySet<string>): boolean {
  if (placeStop.size === 0) return false;
  return intersects(placeStop, new Set(words(normalizeFold(candidate))));
}

function commonsFromUrl(url: string): string | null {
  if (!url) return null;
  // ".../commons/d/d4/AlgerCasbah.jpg" -> "AlgerCasbah.jpg". Deliberately
  // uses `original_url`, not `thumbnail_url` — the latter's "/330px-"
  // size-prefixed final segment would need extra handling to strip.
  // unquote handles accented/spaced filenames the same way wikidata.ts
  // does, for the same reason: avoid double-encoding on the next request.
  return unquote(url.split("/").pop() ?? "") || null;
}

async function fromCommonsFile(filename: string): Promise<PhotoFields | null> {
  const resolved = await resolveCommonsFile(filename);
  if (!resolved) return null;
  return {
    photo_url: resolved.url,
    photo_attribution: resolved.attribution,
    photo_license: resolved.license,
    photo_source_url: resolved.source_url,
  };
}

/**
 * A lead image is only usable once its Commons license is known, so this
 * always round-trips through `resolveCommonsFile` rather than storing the
 * REST thumbnail URL on its own.
 */
async function fromWikipediaSummary(
  summary: WikipediaSummary | null,
): Promise<PhotoFields | null> {
  if (!summary || !summary.thumbnail_url) return null;
  const filename = commonsFromUrl(summary.original_url ?? "");
  if (!filename) return null;
  const resolved = await resolveCommonsFile(filename);
  if (!resolved) return null;
  return {
    photo_url: summary.thumbnail_url,
    photo_attribution: resolved.attribution,
    photo_license: resolved.license,
    photo_source_url: resolved.source_url,
  };
}

interface GeosearchResponse {
  query?: { geosearch?: Array<{ title: string; dist?: number }> };
}

/**
 * Commons files geotagged within `radiusM` of the point, nearest first.
 * Returns [filename, metres] pairs.
 */
async function commonsGeosearch(
  lat: number,
  lng: number,
  limit = 30,
  radiusM: number = COMMONS_GEO_RADIUS_M,
): Promise<Array<[string, number]>> {
  const data = await getJsonOrNull<GeosearchResponse>(
    "https://commons.wikimedia.org/w/api.php",
    {
      action: "query",
      format: "json",
      list: "geosearch",
      gscoord: `${lat}|${lng}`,
      gsradius: radiusM,
      gslimit: limit,
      gsnamespace: 6,
    },
    `Commons geosearch ${lat},${lng}`,
  );
  const results = data?.query?.geosearch ?? [];
  return results.map((r) => [
    r.title.startsWith("File:") ? r.title.slice("File:".length) : r.title,
    r.dist ?? 0.0,
  ]);
}

async function wikipediaGeosearch(
  lat: number,
  lng: number,
  lang: string,
  limit = 15,
): Promise<string[]> {
  const data = await getJsonOrNull<GeosearchResponse>(
    `https://${lang}.wikipedia.org/w/api.php`,
    {
      action: "query",
      format: "json",
      list: "geosearch",
      gscoord: `${lat}|${lng}`,
      gsradius: WIKIPEDIA_GEO_RADIUS_M,
      gslimit: limit,
    },
    `Wikipedia (${lang}) geosearch ${lat},${lng}`,
  );
  return (data?.query?.geosearch ?? []).map((r) => r.title);
}

interface ClaimsResponse {
  claims?: { P18?: Array<{ mainsnak?: { datavalue?: { value?: string } } }> };
}

async function wikidataP18(qid: string): Promise<string | null> {
  const data = await getJsonOrNull<ClaimsResponse>(
    "https://www.wikidata.org/w/api.php",
    { action: "wbgetclaims", entity: qid, property: "P18", format: "json" },
    `Wikidata P18 ${qid}`,
  );
  const claims = data?.claims?.P18 ?? [];
  if (claims.length === 0) return null;
  const value = claims[0]?.mainsnak?.datavalue?.value;
  if (typeof value !== "string") return null;
  // Commons filenames use underscores where Wikidata stores spaces.
  return value.replace(/ /g, "_");
}

interface OpenverseResult {
  url?: string;
  title?: string;
  source?: string;
  license?: string;
  license_version?: string;
  creator?: string;
  foreign_landing_url?: string;
}

async function openverseSearch(query: string, limit = 8): Promise<OpenverseResult[]> {
  const data = await getJsonOrNull<{ results?: OpenverseResult[] }>(
    "https://api.openverse.org/v1/images/",
    { q: query, page_size: limit, license_type: "all-cc" },
    `Openverse search ${JSON.stringify(query)}`,
  );
  return data?.results ?? [];
}

/**
 * Wikimedia-sourced Openverse hits are routed back through
 * `resolveCommonsFile` — that yields the 800px thumbnail and the same
 * attribution string as every other Commons tier, rather than Openverse's
 * link to the multi-megabyte original. Non-Commons sources (Flickr et al.)
 * are stored as-is, with Openverse's own license metadata.
 */
async function fromOpenverse(result: OpenverseResult): Promise<PhotoFields | null> {
  const url = result.url ?? "";
  if (result.source === "wikimedia" && url.includes("/commons/")) {
    const filename = commonsFromUrl(url);
    if (filename) {
      const resolved = await fromCommonsFile(filename);
      if (resolved) return resolved;
    }
  }

  const licenseCode = result.license;
  const creator = result.creator;
  if (!url || !licenseCode || !creator) {
    // Same rule as commons.ts: no attribution, no photo.
    return null;
  }

  const version = result.license_version;
  const licenseName = `CC ${licenseCode.toUpperCase()}` + (version ? ` ${version}` : "");
  return {
    photo_url: url,
    photo_attribution: `${creator} (via Openverse)`,
    photo_license: licenseName,
    photo_source_url: result.foreign_landing_url || url,
  };
}

// How far out to look for a representative photograph when nothing depicting
// the subject itself could be found. Wide enough to reach the nearest
// photographed thing in a town, tight enough that the picture is still of
// somewhere the traveller is standing.
export const NEARBY_FALLBACK_RADIUS_M = 2000;

// Commons holds a great deal that is not a photograph of a place — locator
// maps, coats of arms, flags, plans, scanned documents. They are exactly what
// a proximity-only search surfaces first, and they look broken on a card.
const NON_PHOTO_HINTS = [
  "map", "locator", "carte", "plan", "flag", "drapeau", "coat of arms",
  "blason", "logo", "seal", "diagram", "chart", "schema", "timeline",
  "svg", "icon", "banner", "signature", "document", "scan",
];
const PHOTO_EXTENSIONS = [".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff"];

function looksLikeAPhotograph(filename: string): boolean {
  const lowered = filename.toLowerCase();
  if (!PHOTO_EXTENSIONS.some((ext) => lowered.endsWith(ext))) return false;
  return !NON_PHOTO_HINTS.some((hint) => lowered.includes(hint));
}

/**
 * A real, licensed photograph taken *near* this point — not of it.
 *
 * This deliberately breaks the rule the rest of this module is built on.
 * Every tier above requires a name match precisely because proximity alone
 * picks the wrong subject: the module docstring records "Bir Jebah" getting
 * a portrait of a person and "Kilometre Zero" getting a map. That reasoning
 * still stands, and this function does not overturn it.
 *
 * What changed is the alternative. Most POIs match no tier at all and showed
 * an empty placeholder, and a photograph of the surrounding place — clearly
 * labelled as not being of the subject — is more use to a traveller than
 * nothing. The caller **must** surface `photo_is_stock`; an unlabelled
 * nearby photo would be exactly the silent false positive the strict tiers
 * exist to prevent.
 *
 * Obvious non-photographs are filtered out, since a locator map is what a
 * proximity search offers first and it reads as a broken image on a card.
 */
export async function resolveNearbyPhoto(options: {
  lat: number;
  lng: number;
  radiusM?: number;
}): Promise<PhotoFields | null> {
  const { lat, lng, radiusM = NEARBY_FALLBACK_RADIUS_M } = options;
  for (const [filename] of await commonsGeosearch(lat, lng, 25, radiusM)) {
    if (!looksLikeAPhotograph(filename)) continue;
    const resolved = await fromCommonsFile(filename);
    if (resolved) {
      return {
        ...resolved,
        photo_is_stock: true,
        photo_stock_note: "Nearby photo, not of this place",
      };
    }
  }
  return null;
}

export interface ResolvePhotoOptions {
  wikipediaTitle?: string | null;
  wikidataImageFilename?: string | null;
  osmTags: OsmTags;
  wikidataQid?: string | null;
  name?: string | null;
  lat?: number | null;
  lng?: number | null;
  placeContext?: string | null;
}

/**
 * Returns {photo_url, photo_attribution, photo_license, photo_source_url}
 * from the first tier that resolves, or null.
 *
 * Structured tiers run first and unconditionally: Wikipedia lead image,
 * Wikidata P18 (from the tile SPARQL result, then by QID lookup), then an
 * explicit `wikimedia_commons=File:*` OSM tag. Every one of them goes
 * through `resolveCommonsFile` for license/attribution — a URL is never
 * stored without knowing what it's licensed under.
 *
 * The discovery tiers below them only run when `lat`/`lng` are supplied,
 * and only accept a candidate that is both geographically anchored and a
 * name match. See the module docstring for why either condition alone was
 * measured to be insufficient.
 */
export async function resolvePhoto(options: ResolvePhotoOptions): Promise<PhotoFields | null> {
  const {
    wikipediaTitle,
    wikidataImageFilename,
    osmTags,
    wikidataQid,
    name,
    lat,
    lng,
    placeContext,
  } = options;

  if (wikipediaTitle) {
    const resolved = await fromWikipediaSummary(await fetchSummary(wikipediaTitle));
    if (resolved) return resolved;
  }

  if (wikidataImageFilename) {
    const resolved = await fromCommonsFile(wikidataImageFilename);
    if (resolved) return resolved;
  }

  if (wikidataQid) {
    const filename = await wikidataP18(wikidataQid);
    if (filename) {
      const resolved = await fromCommonsFile(filename);
      if (resolved) return resolved;
    }
  }

  const commonsTag = (osmTags ?? {}).wikimedia_commons ?? "";
  if (typeof commonsTag === "string" && commonsTag.startsWith("File:")) {
    const resolved = await fromCommonsFile(commonsTag.slice("File:".length));
    if (resolved) return resolved;
  }

  const names = nameVariants(name || (osmTags ?? {}).name, osmTags);
  if (names.length === 0 || lat === null || lat === undefined || lng === null || lng === undefined) {
    return null;
  }

  const placeStop = placeStopwords(osmTags, placeContext);
  const variantTokens = names.map((v) => tokens(v, placeStop)).filter((t) => t.size > 0);
  if (variantTokens.length === 0) {
    // Nothing distinctive left to verify against (e.g. a POI named just
    // "Parc", or the node literally named "Ne"). Guessing here is
    // precisely what produces wrong photos.
    return null;
  }

  // Tier: geotagged Commons file whose filename names this subject.
  for (const [filename] of await commonsGeosearch(lat, lng)) {
    if (matchesSubject(filename, variantTokens, placeStop)) {
      const resolved = await fromCommonsFile(filename);
      if (resolved) return resolved;
    }
  }

  // Tier: nearby Wikipedia article whose title names this subject — its
  // lead image is the same well-licensed path as tier 1, just reached
  // without an OSM link.
  for (const lang of ["en", "fr", "ar"]) {
    for (const title of await wikipediaGeosearch(lat, lng, lang)) {
      if (matchesSubject(title, variantTokens, placeStop)) {
        const resolved = await fromWikipediaSummary(await fetchSummary(title, lang));
        if (resolved) return resolved;
      }
    }
  }

  // Tier: Openverse (CC-licensed image search). Query is qualified with the
  // place so the index has some chance of disambiguating, and the result is
  // still name-verified — unguarded it happily returns Venice for "Palace
  // of the Dey".
  // Without a place to corroborate against there is no way to tell a
  // correct hit from a same-named subject on another continent, so the
  // tier is skipped entirely rather than run unguarded.
  if (placeStop.size === 0) {
    return null;
  }

  const qualifier = placeContext ? ` ${placeContext}` : "";
  for (const variant of names.slice(0, 2)) {
    for (const result of await openverseSearch(`${variant}${qualifier}`)) {
      const title = result.title ?? "";
      if (isTagDump(title)) continue;
      if (matchesSubject(title, variantTokens, placeStop) && mentionsPlace(title, placeStop)) {
        const resolved = await fromOpenverse(result);
        if (resolved) return resolved;
      }
    }
  }

  return null;
}
