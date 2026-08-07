/**
 * Overpass client — Stage 1 (Fetch) of the route-generation funnel.
 *
 * docs/backend/12 specifies the query shape: tourism/historic/natural POIs,
 * explicitly excluding accommodation, information boards, and gift shops,
 * which dominate an unfiltered feed and are never a stop on a tour.
 */
import { Deadline, Settled, settle, sleep, waitFirst } from "../async";
import { parseJson, raiseForStatus, request } from "../http";
import { getLogger } from "../logger";
import {
  collapseWhitespace,
  capitalize,
  countDigits,
  countLetters,
  intersects,
  normalizeFold,
  roundTo,
  unionInto,
  compareTuples,
} from "../text";
import { Bounds, OsmTags, Poi } from "../types";

const logger = getLogger("ingestion.overpass");

/**
 * Note what `GET /api/status` reports for these three:
 *
 *   overpass-api.de      -> announced endpoint lambert.openstreetmap.de
 *   z.overpass-api.de    -> announced endpoint gall.openstreetmap.de
 *   lz4.overpass-api.de  -> announced endpoint lambert.openstreetmap.de
 *
 * Three hostnames, **two** actual servers — overpass-api.de and lz4 are the
 * same machine. So the list buys less redundancy than it looks like, and a bad
 * minute on lambert takes out two thirds of it at once.
 */
export const OVERPASS_MIRRORS = [
  "https://overpass-api.de/api/interpreter",
  "https://z.overpass-api.de/api/interpreter",
  "https://lz4.overpass-api.de/api/interpreter",
];

/**
 * The same status endpoint reports `Rate limit: 2` — two concurrent queries
 * per client IP across the whole service, not per host. Hedging three at once
 * therefore *guarantees* the third is refused, and a burst of requests spends
 * slots that then aren't there for the real one. Capping in-flight requests at
 * the documented limit is the difference between hedging and self-inflicted
 * 504s.
 */
export const MAX_CONCURRENT_MIRRORS = 2;

export const TIMEOUT_S = 30;

/**
 * Mirrors are hedged rather than tried strictly in sequence: the next one is
 * started if the previous hasn't answered within this window, and the first
 * usable response wins. Overpass mirror latency is wildly bimodal — a loaded
 * public instance can sit on a request for its full 25 s timeout before
 * failing, which under the old sequential loop put a 50–75 s floor under a
 * route request. Hedging bounds that at roughly one slow mirror's wait.
 *
 * Deliberately a delay rather than firing all three at once: three copies of
 * every query is not fair use of a free shared service, and in the common case
 * where the first mirror is healthy the others are never sent at all.
 */
export const HEDGE_DELAY_S = 5.0;

/**
 * One extra pass over the mirrors after a pause. A 504 from a public Overpass
 * instance means "busy right now", not "no data here" — the same bbox that
 * 504'd on one attempt answers in a few seconds on the next. Without this a
 * momentary wobble is indistinguishable from an empty area, and the user gets
 * an empty route (which is exactly what happened).
 */
export const RETRY_PASSES = 2;
export const RETRY_BACKOFF_S = 3.0;

/**
 * How close two objects must be before a shared name or Wikidata id is read
 * as "same place". Sized from the real misses: the two Martyrs Memorial
 * objects sit 61 m apart, the two Parc de Bentalha ways 121 m, and the Sidi
 * Fredj fort and its viewpoint 246 m. Beyond ~250 m a shared name starts
 * meaning two genuinely different places (a street and the landmark it is
 * named after).
 */
export const DUPLICATE_RADIUS_M = 250;

// Same bbox asked for twice in a row (a retry, a nudged radius, two people in
// the same city) reuses the answer instead of paying Overpass again. POI data
// does not move on this timescale.
const CACHE_TTL_MS = 600 * 1000;

// Entries are kept long past their serving TTL so that a failed fetch can fall
// back on the last known-good answer for the area. Hours-old POI data is a far
// better answer than no route at all, and POIs do not move.
const CACHE_RETAIN_MS = 24 * 3600 * 1000;

const CACHE_MAX = 64;

// A plain Map: the `threading.Lock` the Python version needed around this is
// unnecessary on a single-threaded event loop.
const cache = new Map<string, { storedAt: number; pois: Poi[] }>();

const EXCLUDED_TOURISM = new Set([
  "hotel",
  "hostel",
  "guest_house",
  "apartment",
  "motel",
  "camp_site",
  "caravan_site",
  "chalet",
  "information",
  "picnic_site",
]);

/**
 * The same exclusion, pushed down into the query instead of only being applied
 * to the response. Accommodation and information boards are the bulk of
 * `tourism=*` in any city, and every one of them was being matched, serialized,
 * transferred and then dropped by `categoryFromTags`.
 *
 * This cannot lose a POI: the union's other clauses are unconditional, so a
 * hotel that is also `historic=castle` still arrives via `node["historic"]`,
 * and a `tourism=hotel` with nothing else was already discarded on arrival.
 */
const TOURISM_FILTER = `["tourism"!~"^(${[...EXCLUDED_TOURISM].sort().join("|")})$"]`;

/**
 * `out tags bb` rather than `out center`: Overpass's "center" *is* the midpoint
 * of the bounding box, so this loses nothing and gains each way's extent —
 * which is what lets the route avoid spending three of its eight stops inside
 * one archaeological park (see `dropEnclosed` in routes/itinerary.ts). Costs
 * about 20% more response bytes.
 */
function buildQuery(latMin: number, lngMin: number, latMax: number, lngMax: number): string {
  const bbox = `(${latMin},${lngMin},${latMax},${lngMax})`;
  return `
[out:json][timeout:25];
(
  node["tourism"]${TOURISM_FILTER}${bbox};
  way ["tourism"]${TOURISM_FILTER}${bbox};

  node["historic"]${bbox};
  way ["historic"]${bbox};

  node["natural"~"^(peak|cave_entrance|arch|spring|beach|bay|cape|cliff|glacier|volcano|water)$"]${bbox};
  way ["natural"~"^(beach|bay|cape|cliff|glacier|volcano|water)$"]${bbox};
  way ["waterway"="waterfall"]${bbox};

  node["leisure"~"^(park|garden|water_park|beach_resort|stadium)$"]${bbox};
  way ["leisure"~"^(park|garden|water_park|beach_resort|stadium)$"]${bbox};

  node["shop"="mall"]${bbox};
  way ["shop"="mall"]${bbox};
  node["amenity"~"^(marketplace|theatre|cinema|arts_centre)$"]${bbox};
  way ["amenity"~"^(marketplace|theatre|cinema|arts_centre)$"]${bbox};
);
out tags bb;
`;
}

// Tag values that say a tag is *present* without saying what the thing is.
// `historic=yes` is the common one, and taken literally it produced the
// category "Yes" on the app's cards — two Algiers mosques shipped labelled
// "Yes" because that is what `historic` said about them.
const UNINFORMATIVE_VALUES = new Set(["yes", "true", "1"]);

// `historic` values that are real but still less descriptive of what the
// place *is* than another tag on the same object. "Ketchaoua Mosque —
// Heritage" is worse than "Ketchaoua Mosque — Mosque".
const WEAK_HISTORIC_VALUES = new Set(["heritage", "building", "yes"]);

const LEISURE_CATEGORIES: Record<string, string> = {
  park: "Park",
  garden: "Garden",
  water_park: "Water park",
  beach_resort: "Beach resort",
  stadium: "Stadium",
};

const AMENITY_CATEGORIES: Record<string, string> = {
  marketplace: "Market",
  theatre: "Theatre",
  cinema: "Cinema",
  arts_centre: "Arts centre",
};

const WORSHIP_BY_RELIGION: Record<string, string> = {
  muslim: "Mosque",
  christian: "Church",
  jewish: "Synagogue",
  buddhist: "Temple",
  hindu: "Temple",
};

const NATURAL_CATEGORIES: Record<string, string> = {
  peak: "Peak",
  cave_entrance: "Cave",
  arch: "Natural arch",
  spring: "Spring",
  beach: "Beach",
  bay: "Bay",
  cape: "Cape",
  cliff: "Cliff",
  glacier: "Glacier",
  volcano: "Volcano",
  water: "Water",
};

/**
 * Places that carry a tourism/historic/leisure tag but that nobody can
 * actually visit. Embassies are the case that forced this: they are tagged
 * `office=diplomatic` *and* `leisure=park` (their walled gardens), which under
 * the old rules scored them as parks — four of the top ten Algiers candidates
 * were embassies, ahead of the Casbah's mosques.
 *
 * `null` means "any value at all".
 */
const EXCLUDED_TAG_VALUES = new Map<string, Set<string> | null>([
  ["office", new Set(["diplomatic", "government", "administrative"])],
  [
    "amenity",
    new Set([
      "embassy",
      "prison",
      "police",
      "fire_station",
      "hospital",
      "school",
      "college",
      "kindergarten",
      "fuel",
      "parking",
    ]),
  ],
  ["diplomatic", null],
  ["embassy", null],
  ["landuse", new Set(["industrial"])],
  // `barrier` is deliberately absent as a blanket rule — historic city walls
  // carry it, and so does the Serkadji Prison museum. See the walled-enclosure
  // penalty in scoring.ts for the narrow case it does matter in.
]);

// Active military installations aren't visitable, but a great many *visitable*
// forts and citadels are tagged `military=*` too (`historic=fort` +
// `military=bunker` is standard). So military tags only exclude when nothing
// else says the object is a heritage site.
const MILITARY_KEYS = new Map<string, Set<string> | null>([
  ["military", null],
  ["landuse", new Set(["military"])],
]);

/**
 * Whether this object is something a traveller cannot visit, regardless
 * of what other tags it happens to carry.
 *
 * Only unambiguous cases belong here, because this drops a POI outright. A
 * walled compound tagged `leisure=park` is *usually* a private residence but
 * sometimes a real monument with poor tagging, so it is penalized in
 * `ingestion/scoring.ts` rather than excluded — see the note there.
 */
export function isExcluded(tags: OsmTags): boolean {
  for (const [key, blocked] of EXCLUDED_TAG_VALUES) {
    const value = tags[key];
    if (value === undefined || value === null) continue;
    if (blocked === null || blocked.has(value)) return true;
  }

  const historic = tags.historic;
  if (historic && !UNINFORMATIVE_VALUES.has(historic)) {
    return false;
  }
  for (const [key, blocked] of MILITARY_KEYS) {
    const value = tags[key];
    if (value !== undefined && value !== null && (blocked === null || blocked.has(value))) {
      return true;
    }
  }
  return false;
}

/** Python's `value.replace("_", " ").capitalize()`. */
function clean(value: string): string {
  return capitalize(value.replace(/_/g, " "));
}

/**
 * Normalizes the several OSM tagging schemes this query touches into one
 * display category.
 *
 * `historic` still leads — heritage sites are this app's subject — but only
 * when it actually says something. A `historic` of `yes`/`heritage`/
 * `building` describes the object's status, not its kind, so those fall
 * through to whatever tag does describe it (`amenity=place_of_worship`,
 * `tourism`, `natural`, …) and are used only as a last resort.
 */
export function categoryFromTags(tags: OsmTags): string | null {
  if (isExcluded(tags)) {
    return null;
  }

  const historic = tags.historic;
  if (historic && !WEAK_HISTORIC_VALUES.has(historic)) {
    return clean(historic);
  }

  if (tags.amenity === "place_of_worship") {
    const religion = tags.religion ?? "";
    if (religion in WORSHIP_BY_RELIGION) {
      return WORSHIP_BY_RELIGION[religion];
    }
    const building = tags.building ?? "";
    if (["mosque", "church", "synagogue", "temple", "cathedral", "chapel"].includes(building)) {
      return clean(building);
    }
    return "Place of worship";
  }

  const tourism = tags.tourism;
  if (tourism && !EXCLUDED_TOURISM.has(tourism) && !UNINFORMATIVE_VALUES.has(tourism)) {
    return clean(tourism);
  }

  if ("natural" in tags) {
    const value = tags.natural as string;
    return NATURAL_CATEGORIES[value] ?? clean(value);
  }
  if (tags.waterway === "waterfall") {
    return "Waterfall";
  }

  const leisure = tags.leisure;
  if (leisure && leisure in LEISURE_CATEGORIES) {
    return LEISURE_CATEGORIES[leisure];
  }

  // Destination retail and performing arts. Deliberately narrow: `shop=mall`
  // and `amenity=marketplace` are places people set out to visit, whereas
  // `shop=*` in general is every corner store in the city. A route request
  // that says "shopping malls" had nothing to select before this — the
  // Bab Ezzouar mall (`shop=mall`, and it has a Wikidata id) was not merely
  // ranked low, it was never fetched.
  if (tags.shop === "mall") {
    return "Shopping mall";
  }
  const amenity = tags.amenity;
  if (amenity && amenity in AMENITY_CATEGORIES) {
    return AMENITY_CATEGORIES[amenity];
  }

  // Nothing said what it is, but `historic=heritage` at least says it
  // matters. `historic=yes` says nothing at all and is not a category.
  if (historic && !UNINFORMATIVE_VALUES.has(historic)) {
    return clean(historic);
  }
  if (historic) {
    return "Historic site";
  }
  return null;
}

/** The pure tag rules, exposed for the parity harness. See photos.ts. */
export const internals = {
  clean: (value: string) => clean(value),
  richness: (poi: Poi) => richness(poi),
  splitMulti: (value: string | null | undefined) => splitMulti(value),
};

const NAME_KEYS = new Set([
  "name",
  "alt_name",
  "int_name",
  "official_name",
  "short_name",
  "reg_name",
]);

/**
 * A trailing "2" / "no 2" / "n 3" — a mapper's disambiguation suffix, not part
 * of the name. Anchored to the end so "Route 66" or "Place du 1er Novembre"
 * (where the number carries meaning mid-name) are untouched.
 *
 * `\p{Nd}` rather than `\d`, because Python's `\d` matches Arabic-Indic digits
 * and JavaScript's does not.
 */
const TRAILING_INDEX_RE = /\s+(?:no|n|nr|num|numero)?\s*\p{Nd}{1,2}$/u;

/**
 * Whether a `name` value names the place or is a catalogue reference.
 *
 * Heritage-register ids get tagged as names surprisingly often — Algiers
 * alone returns artworks named `214145`, `937605` and `116pa466551`. They
 * are unusable on a card and meaningless to the LLM, and they defeat
 * deduplication because two references never match.
 */
export function isRealName(name: string): boolean {
  const letters = countLetters(name);
  const digits = countDigits(name);
  return letters >= 3 && letters > digits;
}

function nameFromTags(tags: OsmTags): string | null {
  // English-first since only 'en' translations are populated today
  // (docs/backend/09 covers multilingual content; not wired up yet).
  for (const value of [tags["name:en"], tags.int_name, tags.name]) {
    if (value && isRealName(value)) return value;
  }
  return null;
}

/**
 * Every name this object is known by, normalized for comparison.
 *
 * All languages, deliberately: the duplicate that shows up as two cards is
 * usually the *same* subject carrying different display names — a way named
 * "Martyrs Memorial" and a node named "مقام الشهداء" whose `name:en` is also
 * "martyrs memorial". Comparing display names alone would never catch it.
 */
export function nameVariants(tags: OsmTags): Set<string> {
  const out = new Set<string>();
  for (const [key, value] of Object.entries(tags)) {
    if (typeof value !== "string") continue;
    if (!NAME_KEYS.has(key) && !key.startsWith("name:")) continue;
    // OSM packs multiple values into one tag with semicolons
    // ("Dar Aziza;Palais de la Djenina"), and a merged duplicate's name is
    // appended to `alt_name` the same way below.
    for (const rawPart of value.split(";")) {
      const part = rawPart.trim();
      if (!isRealName(part)) continue;
      const normalized = collapseWhitespace(normalizeFold(part));
      if (!normalized) continue;
      out.add(normalized);
      // Mappers disambiguate a second object for one subject by
      // suffixing a number — "Martyrs Memorial" the monument and
      // "Martyrs Memorial 2" the viewpoint node 94 m away. Comparing
      // the de-numbered form too catches those without merging places
      // that merely sit near each other.
      const base = normalized.replace(TRAILING_INDEX_RE, "").trim();
      if (base && base !== normalized && base.length >= 4) {
        out.add(base);
      }
    }
  }
  return out;
}

/** OSM's semicolon-separated multi-value convention. */
function splitMulti(value: string | null | undefined): string[] {
  return (value ?? "")
    .split(";")
    .map((part) => part.trim())
    .filter((part) => part.length > 0);
}

/**
 * Sort key for "which of these duplicates should survive". Prefers a
 * knowledge-base link, then a specific category, then raw tag count.
 */
function richness(poi: Poi): number[] {
  const tags = poi.tags;
  return [
    tags.wikidata || tags.wikipedia ? 1 : 0,
    tags.wikimedia_commons ? 1 : 0,
    ["Attraction", "Historic site", "Place of worship"].includes(poi.category) ? 0 : 1,
    Object.keys(tags).length,
  ];
}

/**
 * Metres between two POIs. Equirectangular rather than haversine — this
 * runs O(kept) times per POI and is only ever compared against a 250 m
 * threshold, where the two agree to well under a metre.
 */
export function distanceM(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const toRad = (deg: number): number => (deg * Math.PI) / 180;
  const meanLat = toRad((a.lat + b.lat) / 2);
  const dx = toRad(a.lng - b.lng) * Math.cos(meanLat);
  const dy = toRad(a.lat - b.lat);
  return Math.hypot(dx, dy) * 6371000.0;
}

/**
 * Collapse POIs that are the same real-world subject.
 *
 * OSM routinely holds one place several times — a way for the building and
 * a node for the viewpoint on top of it, or two ways digitized by different
 * mappers — each with its own name in its own language. Untouched, they
 * become separate cards in the same route: Algiers returned "Martyrs
 * Memorial" (way), "Martyrs Memorial" (node, tagged as a viewpoint) and
 * "MaQam echahid" (node) — three cards, 61 m apart, all the same monument.
 *
 * Two objects are the same subject when they are **close together** and
 * either share a Wikidata id or share a name variant. Both halves are
 * required. Proximity alone is wrong (a café next to a mosque is not the
 * mosque) and identity alone is wrong too — `Ben Aknoun Zoo` and `Ben Aknoun
 * Amusement Park` carry the same Wikidata id 1.8 km apart and are genuinely
 * two places.
 *
 * The survivor is the richest record, and it inherits the others' tags, so
 * name variants and any `wikidata`/`wikipedia` link from a dropped duplicate
 * still reach photo resolution.
 */
export function deduplicate(pois: Poi[]): Poi[] {
  // Python's `sorted(..., reverse=True)` is stable; so is Array#sort.
  const ordered = [...pois].sort((a, b) => compareTuples(richness(b), richness(a)));
  const kept: Poi[] = [];
  const keptVariants: Array<Set<string>> = [];

  for (const poi of ordered) {
    const variants = nameVariants(poi.tags);
    const qid = poi.tags.wikidata;

    let mergedIndex = -1;
    for (let i = 0; i < kept.length; i++) {
      if (distanceM(poi, kept[i]) > DUPLICATE_RADIUS_M) continue;
      const existingQid = kept[i].tags.wikidata;
      if ((qid && qid === existingQid) || intersects(variants, keptVariants[i])) {
        mergedIndex = i;
        break;
      }
    }

    if (mergedIndex === -1) {
      kept.push(poi);
      keptVariants.push(variants);
      continue;
    }

    const survivor = kept[mergedIndex];
    // The survivor's own values win; the duplicate only fills gaps.
    for (const [key, value] of Object.entries(poi.tags)) {
      if (!(key in survivor.tags)) survivor.tags[key] = value;
    }

    // Filling gaps cannot carry over the duplicate's *display* name — the
    // survivor always has a `name` of its own — so it is appended to
    // `alt_name` instead. That name is often the only one in a given
    // language ("MaQam echahid" for the memorial whose `name` is English),
    // and photo resolution matches Commons filenames against exactly these
    // variants, so dropping it would cost real matches.
    const droppedName = poi.tags.name;
    if (droppedName && !splitMulti(survivor.tags.alt_name).includes(droppedName)) {
      if (droppedName !== survivor.tags.name) {
        const existingAlt = survivor.tags.alt_name;
        survivor.tags.alt_name = existingAlt ? `${existingAlt};${droppedName}` : droppedName;
      }
    }

    unionInto(keptVariants[mergedIndex], variants);
    survivor.wikidata_qid = survivor.wikidata_qid || poi.wikidata_qid || null;
    survivor.wikipedia = survivor.wikipedia || poi.wikipedia || null;
  }

  return kept;
}

/**
 * Raised when Overpass can't be reached or returns something unusable.
 *
 * Deliberately **not** swallowed into an empty list here — that was the
 * original design and it produced a real bug during live testing: a 504
 * from Overpass (hit for real, mid-ingestion, on a shared public instance)
 * resulted in `ingestOneTile` finishing with zero POIs and the tile
 * getting cached as `fetch_status='ok', poi_count=0` for the normal 60-day
 * TTL. That's indistinguishable from "this tile genuinely has nothing in
 * it" and silently poisons the cache for two months over a transient
 * timeout. Raising here lets `ingestion/ingest.ts`'s existing tile-level
 * exception handling do the right thing instead — mark the tile `failed`
 * with a 1-day retry TTL, which is what already happens for every other
 * exception in that path; Overpass failures just weren't reaching it.
 */
export class OverpassError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OverpassError";
  }
}

/**
 * ~100 m of rounding: finer than that and the cache never hits, because
 * the bbox is derived from a GPS fix that jitters on every request.
 */
function cacheKey(latMin: number, lngMin: number, latMax: number, lngMax: number): string {
  return [latMin, lngMin, latMax, lngMax].map((v) => roundTo(v, 3)).join(",");
}

/**
 * Cached POIs for a bbox. `maxAgeMs` is widened by the failure path to accept
 * a stale entry rather than return nothing.
 */
function cacheGet(key: string, maxAgeMs: number = CACHE_TTL_MS): Poi[] | null {
  const entry = cache.get(key);
  if (entry === undefined) return null;
  const age = Date.now() - entry.storedAt;
  if (age > maxAgeMs) {
    if (age > CACHE_RETAIN_MS) cache.delete(key);
    return null;
  }
  return entry.pois;
}

function cachePut(key: string, pois: Poi[]): void {
  if (cache.size >= CACHE_MAX) {
    let oldestKey: string | null = null;
    let oldestAt = Infinity;
    for (const [k, v] of cache) {
      if (v.storedAt < oldestAt) {
        oldestAt = v.storedAt;
        oldestKey = k;
      }
    }
    if (oldestKey !== null) cache.delete(oldestKey);
  }
  cache.set(key, { storedAt: Date.now(), pois });
}

interface OverpassElement {
  type: string;
  id: number;
  lat?: number;
  lon?: number;
  bounds?: Bounds;
  center?: { lat?: number; lon?: number };
  tags?: OsmTags;
}

/** One mirror's raw `elements`. Rejects on anything unusable. */
async function queryMirror(
  url: string,
  query: string,
  signal: AbortSignal,
): Promise<OverpassElement[]> {
  const response = await request(url, {
    method: "POST",
    form: { data: query },
    timeoutMs: TIMEOUT_S * 1000,
    // An abandoned hedge is cancelled rather than left to finish — the Python
    // could only `shutdown(wait=False)` and let it run to completion against a
    // service with a documented two-query limit.
    signal,
  });
  if (response.status === 429) {
    throw new OverpassError(`429 Too Many Requests from ${url}`);
  }
  await raiseForStatus(response, url);
  const data = await parseJson<{ elements?: OverpassElement[] }>(response, url);
  return data.elements ?? [];
}

/**
 * First usable response from any mirror, hedged and then retried.
 *
 * A single pass over the mirrors is not enough on a free shared service:
 * all three can be busy at the same moment and all three return 504, which
 * is a temporary state, not an answer about the area.
 */
async function fetchElements(query: string): Promise<OverpassElement[]> {
  let lastError: Error | null = null;
  for (let attempt = 0; attempt < RETRY_PASSES; attempt++) {
    if (attempt) {
      await sleep(RETRY_BACKOFF_S * attempt * 1000);
      logger.info(`Overpass retry pass ${attempt + 1}/${RETRY_PASSES}`);
    }
    try {
      return await fetchElementsOnce(query);
    } catch (error) {
      if (!(error instanceof OverpassError)) throw error;
      lastError = error;
    }
  }
  throw lastError ?? new OverpassError("Overpass failed with no error recorded");
}

/** One hedged pass over the mirrors (see HEDGE_DELAY_S). */
async function fetchElementsOnce(query: string): Promise<OverpassElement[]> {
  const controller = new AbortController();
  const pending: Array<Settled<OverpassElement[]>> = [];
  const processed = new Set<Settled<OverpassElement[]>>();
  let lastErr: string | null = null;

  const outstanding = (): Array<Settled<OverpassElement[]>> =>
    pending.filter((f) => !processed.has(f));

  /**
   * Consume whichever mirrors have answered. Returns their elements if one
   * succeeded, otherwise records the failure and returns null.
   */
  const drain = async (
    done: Array<Settled<OverpassElement[]>>,
  ): Promise<OverpassElement[] | null> => {
    for (const future of done) {
      if (processed.has(future)) continue;
      processed.add(future);
      const result = await future.promise;
      if (result.ok) return result.value;
      lastErr = result.error instanceof Error ? result.error.message : String(result.error);
      logger.info(`Overpass mirror failed: ${lastErr}`);
    }
    return null;
  };

  try {
    for (let index = 0; index < OVERPASS_MIRRORS.length; index++) {
      // Never exceed the service's concurrent-query limit: wait for a
      // slot to free up before hedging onto the next mirror.
      while (outstanding().length >= MAX_CONCURRENT_MIRRORS) {
        const done = await waitFirst(outstanding(), TIMEOUT_S * 1000);
        if (done.length === 0) break;
        const won = await drain(done);
        if (won) return won;
      }

      pending.push(settle(queryMirror(OVERPASS_MIRRORS[index], query, controller.signal)));
      const isLast = index === OVERPASS_MIRRORS.length - 1;
      // After the last mirror there is nothing left to hedge with, so
      // wait out the full timeout rather than the hedge window.
      const deadline = new Deadline((isLast ? TIMEOUT_S : HEDGE_DELAY_S) * 1000);

      for (;;) {
        // Only ever wait on mirrors that haven't answered yet. Including
        // settled ones would make the wait return instantly forever after the
        // first failure, and the last iteration would then declare total
        // failure while two mirrors were still in flight.
        const out = outstanding();
        const remaining = deadline.remainingMs();
        if (out.length === 0 || remaining <= 0) break;

        const done = await waitFirst(out, remaining);
        if (done.length === 0) break; // nothing yet — hedge with the next mirror
        const won = await drain(done);
        if (won) return won;
      }
    }

    throw new OverpassError(`All Overpass mirrors failed. Last error: ${lastErr}`);
  } finally {
    // Don't leave hedged requests we no longer need running against a free
    // shared service. `settle` already absorbed their rejections.
    controller.abort();
  }
}

/**
 * Raw POIs from Overpass, already filtered to named + categorized and
 * deduplicated — the noise Overpass returns alongside real POIs (unnamed
 * benches, `tourism=information` signs, embassy compounds tagged as parks,
 * heritage-register ids masquerading as names, and the same monument held
 * two or three times over) is dropped here rather than passed on to scoring.
 *
 * Deduplication lives at this layer on purpose. It is a property of the
 * source — OSM genuinely stores one place as several objects — not of any
 * one consumer, so both the itinerary path and `ingestion/ingest.ts` get it
 * without either having to know.
 *
 * Rejects with `OverpassError` on failure — see that class's docstring for why
 * this isn't a quiet `[]` return.
 */
export async function fetchPois(
  latMin: number,
  lngMin: number,
  latMax: number,
  lngMax: number,
): Promise<Poi[]> {
  const key = cacheKey(latMin, lngMin, latMax, lngMax);
  const cached = cacheGet(key);
  if (cached !== null) {
    logger.info(`Overpass cache hit for ${key} (${cached.length} POIs)`);
    return cached;
  }

  const query = buildQuery(latMin, lngMin, latMax, lngMax);
  let elements: OverpassElement[];
  try {
    elements = await fetchElements(query);
  } catch (error) {
    if (!(error instanceof OverpassError)) throw error;
    // Last resort before giving up: the last good answer for this bbox,
    // however old. POIs do not move, and a day-old candidate list beats
    // the empty route a transient 504 would otherwise produce.
    const stale = cacheGet(key, CACHE_RETAIN_MS);
    if (stale !== null) {
      logger.warning(`Overpass failed for ${key} — serving ${stale.length} stale POIs`);
      return stale;
    }
    throw error;
  }

  const pois: Poi[] = [];
  for (const el of elements) {
    const tags = el.tags ?? {};
    const name = nameFromTags(tags);
    const category = categoryFromTags(tags);
    if (!name || !category) continue;

    let bounds: Bounds | null = null;
    let poiLat: number | undefined;
    let poiLng: number | undefined;

    if (el.type === "node") {
      poiLat = el.lat;
      poiLng = el.lon;
    } else {
      bounds = el.bounds ?? null;
      if (bounds) {
        // Overpass's `center` is defined as the bounding box midpoint,
        // so deriving it here is identical to what `out center` returned.
        poiLat = (bounds.minlat + bounds.maxlat) / 2;
        poiLng = (bounds.minlon + bounds.maxlon) / 2;
      } else {
        const center = el.center ?? {};
        poiLat = center.lat;
        poiLng = center.lon;
      }
    }
    if (poiLat === undefined || poiLat === null || poiLng === undefined || poiLng === null) {
      continue;
    }

    pois.push({
      osm_type: el.type,
      osm_id: el.id,
      name,
      category,
      lat: poiLat,
      lng: poiLng,
      // null for nodes, which have no extent — an enclosure test
      // against a node is meaningless and is skipped.
      bounds,
      tags,
      wikidata_qid: tags.wikidata ?? null,
      wikipedia: tags.wikipedia ?? null, // "en:Casbah of Algiers" form
    });
  }

  const deduped = deduplicate(pois);
  if (deduped.length !== pois.length) {
    logger.info(`Overpass ${key}: ${pois.length} POIs -> ${deduped.length} after dedupe`);
  }

  cachePut(key, deduped);
  return deduped;
}
