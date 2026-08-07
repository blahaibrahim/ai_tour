/**
 * Stage 3 of the route-generation funnel (docs/backend/08, docs/backend/12):
 *
 *     1. Fetch    maps API -> raw POIs                     (ingestion/overpass.ts)
 *     2. Score    deterministic interest ranking           (ingestion/scoring.ts)
 *     3. Select   LLM picks + orders from vetted candidates (this file)
 *
 * ## Where candidates come from
 *
 * Both routes here build candidates by calling Overpass live, through the one
 * shared `buildCandidates`. They do **not** read the `locations` catalogue.
 *
 * That is a change from the original design, in which stages 1+2 ran only via
 * `POST /api/poi/ingest` (routes/poi.ts) into Supabase's `locations` table and
 * this file queried it through the `nearby_locations` RPC. Live Overpass is now
 * fast enough for the request path (`ingestion/overpass.ts` hedges mirrors and
 * caches by bbox), and it removes a hard dependency on someone having ingested
 * an area first — a cold city returned only the 8 curated seed rows.
 *
 * `/api/itinerary` had already moved to live Overpass; `/api/itinerary/modify`
 * had not, and the mismatch was silently destructive. Generate returned
 * `osm-{type}-{id}` ids, modify validated the client's `existing_stops` against
 * uuid-keyed catalogue rows, so no current stop was ever a valid pick and every
 * modify replaced the whole route instead of adjusting it. One builder, one id
 * space, is what fixes that.
 *
 * The catalogue still exists and `/api/poi/ingest` still populates it — it is
 * what `data/locationsRepo.ts` serves, what semantic search runs over, and the
 * **fallback** when Overpass is unreachable (`catalogueCandidates`). Overpass
 * is a free shared service that really does return 504 on all three mirrors at
 * once; when it does, a stale-but-real candidate list is the difference between
 * a usable route and an empty screen.
 */
import { Router } from "express";

import { awaitWithin, createLimiter, Deadline, sleep } from "../async";
import { getTravelTimeMatrix, haversineKm } from "../data/geo";
import { locationsWithinRadius } from "../data/locationsRepo";
import { collectFacts, describe } from "../ingestion/describe";
import { fetchPois } from "../ingestion/overpass";
import { resolveNearbyPhoto, resolvePhoto } from "../ingestion/photos";
import { computeScore } from "../ingestion/scoring";
import { getAdminClient } from "../ingestion/supabaseAdmin";
import { fetchSummary } from "../ingestion/wikipedia";
import { extractJson, JsonExtractionError } from "../jsonUtils";
import { chat, Intent, LLMError } from "../llm";
import { getLogger } from "../logger";
import { authenticateAndRateLimit } from "../rateLimit";
import { unwrap, unwrapRows } from "../supabase";
import { collapseWhitespace } from "../text";
import { Candidate, ChatMessage, LlmPick, PhotoFields } from "../types";
import { asyncHandler } from "./asyncHandler";

const logger = getLogger("routes.itinerary");

export const itineraryRouter = Router();

const MAX_RADIUS_KM = 500;
const MAX_WANTED_VISITS = 20;

/**
 * How many of the ranked candidates get their photo fetched. Photo resolution
 * is several HTTP round trips per POI, and it used to run *after* the LLM had
 * picked — pure added latency at the end of the request. Fetching the top of
 * the ranked list while the model is still choosing makes it nearly free,
 * since the picks come from that top slice. A few extra fetches for candidates
 * that don't get picked cost nothing on the critical path.
 */
const PHOTO_PREFETCH = 16;

/** How many ranked candidates are kept at all. */
const CANDIDATE_LIMIT = 50;

/**
 * Ranked candidates offered to the model. 50 lines of blurb is a large prompt
 * for a choice that is effectively made in the top half of the list.
 */
const LLM_CANDIDATE_LIMIT = 30;

/**
 * Blurbs are context for the pick, not content — the full text goes to the
 * client from the candidate record either way.
 */
const BLURB_CHARS_FOR_LLM = 140;

/**
 * Ceiling on how long the finished route waits for outstanding photo and
 * description lookups. A missing thumbnail is a placeholder in the UI; a route
 * that never arrives is a broken feature. Raised from 8 s once the nearby-photo
 * fallback was added: the extra Commons round trips were pushing the *most*
 * interesting stops past the deadline, so the mall with a Wikipedia article
 * came back with no image at all while its neighbours got one.
 */
const PHOTO_WAIT_S = 14.0;

/**
 * Card-sized. Long enough for a real opening paragraph, short enough that the
 * card stays a card.
 */
const BLURB_MAX_CHARS = 320;

/** Concurrency of the photo/blurb lookups, formerly `ThreadPoolExecutor(8)`. */
const PHOTO_CONCURRENCY = 8;

type PhotoFuture = Promise<PhotoFields | null>;

/**
 * Greedy nearest-neighbor ordering from the user's position. This is the
 * "geometry chooses the order" half of docs/backend/08's Feature 1 — the
 * LLM is never asked to do this.
 */
function orderNearestNeighbor(
  startLat: number,
  startLng: number,
  stops: Candidate[],
): Candidate[] {
  let remaining = [...stops];
  const ordered: Candidate[] = [];
  let curLat = startLat;
  let curLng = startLng;
  while (remaining.length > 0) {
    let next = remaining[0];
    let bestDistance = haversineKm(curLat, curLng, next.lat, next.lng);
    for (const stop of remaining.slice(1)) {
      const distance = haversineKm(curLat, curLng, stop.lat, stop.lng);
      if (distance < bestDistance) {
        next = stop;
        bestDistance = distance;
      }
    }
    ordered.push(next);
    // Identity, not equality: dropping the first *equal* stop is not
    // necessarily dropping this one.
    remaining = remaining.filter((s) => s !== next);
    curLat = next.lat;
    curLng = next.lng;
  }
  return ordered;
}

/**
 * Order stops using real road travel times. Falls back to nearest-neighbor
 * haversine if the OSRM routing engine fails or returns invalid data.
 */
async function orderTravelTime(
  startLat: number,
  startLng: number,
  stops: Candidate[],
): Promise<Candidate[]> {
  if (stops.length === 0) {
    return [];
  }

  const coords: Array<[number, number]> = [
    [startLat, startLng],
    ...stops.map((s): [number, number] => [s.lat, s.lng]),
  ];
  const matrix = await getTravelTimeMatrix(coords);

  if (matrix === null) {
    return orderNearestNeighbor(startLat, startLng, stops);
  }

  // Greedy nearest-neighbor using travel time instead of straight line.
  // Positions are captured up front by identity: the old `stops.index(stop)`
  // both rescanned the list on every comparison and returned the *first*
  // equal stop, which silently mis-indexed the matrix whenever two stops
  // compared equal.
  const matrixIndex = new Map<Candidate, number>(stops.map((s, i) => [s, i + 1]));
  let remaining = [...stops];
  const ordered: Candidate[] = [];
  let curIdx = 0; // 0 is the start point

  while (remaining.length > 0) {
    let bestTime = Infinity;
    let bestStop: Candidate | null = null;
    let bestStopIdx = -1;

    for (const stop of remaining) {
      const stopIdx = matrixIndex.get(stop) as number;
      // duration from curIdx to stopIdx
      const timeS = matrix[curIdx]?.[stopIdx];
      if (timeS !== null && timeS !== undefined && timeS < bestTime) {
        bestTime = timeS;
        bestStop = stop;
        bestStopIdx = stopIdx;
      }
    }

    if (bestStop === null) {
      // Should only happen if the matrix has nulls (unroutable).
      // Fall back to appending remaining by haversine distance.
      ordered.push(
        ...orderNearestNeighbor(coords[curIdx][0], coords[curIdx][1], remaining),
      );
      break;
    }

    ordered.push(bestStop);
    remaining = remaining.filter((s) => s !== bestStop);
    curIdx = bestStopIdx;
  }

  return ordered;
}

function candidateLine(c: Candidate): string {
  return (
    `- id=${c.id} | ${c.name} | ${c.category} | ${c.region ?? "Algeria"} | ` +
    `${(c.distance_km ?? 0).toFixed(1)} km away | ${(c.blurb ?? "").slice(0, BLURB_CHARS_FOR_LLM)}`
  );
}

function parsePicks(raw: string): LlmPick[] {
  const parsed = extractJson(raw);
  const stops = parsed.stops;
  return Array.isArray(stops) ? (stops as LlmPick[]) : [];
}

/**
 * Returns a list of {location_id, reason, suggested_order} picks, already
 * validated against `candidates`. Never returns an id the model invented.
 */
async function selectWithLlm(
  candidates: Candidate[],
  prompt: string,
  wantedVisits: number | null,
  existingStops: Array<Record<string, unknown>> | null = null,
): Promise<LlmPick[]> {
  const candidateLines = candidates.map(candidateLine).join("\n");
  const visitsLine = wantedVisits
    ? `You MUST select exactly 8 stops (or all of them if there are fewer than 8 candidates). They eventually want to reach ${wantedVisits} stops.`
    : "You MUST select exactly 8 stops (or all of them if there are fewer than 8 candidates).";

  const existingLine =
    existingStops && existingStops.length > 0
      ? `Currently they have these stops: ${existingStops
          .map((s) => (s.name as string | undefined) ?? "Unknown")
          .join(", ")}\n`
      : "";

  const messages: ChatMessage[] = [
    {
      role: "system",
      content:
        "You are planning a walking/driving tour in Algeria. Every " +
        "candidate location has already been verified to exist and to " +
        "be worth visiting — your job is fit to the traveller's " +
        "request, not quality. Choose ONLY from the given candidates " +
        "and never invent a location. Reply with a single JSON object " +
        'shaped exactly like: {"stops": [{"location_id": "...", ' +
        '"reason": "one sentence, addressed to the traveller", ' +
        '"suggested_order": 0}]}. No prose outside the JSON.',
    },
    {
      role: "user",
      content:
        `Traveller's request: "${prompt}"\n` +
        `${visitsLine}\n\n` +
        existingLine +
        `Candidates:\n${candidateLines}`,
    },
  ];

  // This call is the whole route's critical path — the user is on the
  // thinking screen for exactly as long as it takes. Picking 8 ids out of a
  // pre-vetted list is a selection task, not a reasoning one: every
  // candidate has already been verified and scored before it gets here, and
  // anything the model invents is rejected below regardless. So it asks for
  // the fast provider and minimal thinking; both fall back exactly as
  // before if that path is unavailable. Measured on this prompt: ~1.6s here
  // against ~16s for the previous gemini/'medium' default, same 8 stops.
  const raw = await chat(messages, {
    jsonMode: true,
    maxTokens: 1024,
    temperature: 0.6,
    thinkingLevel: "minimal",
    prefer: "groq",
  });

  let stops: LlmPick[];
  try {
    stops = parsePicks(raw);
  } catch (error) {
    logger.error(`Failed to extract JSON from LLM: ${raw}`);
    throw new Error("Could not parse LLM output", { cause: error });
  }

  const candidateIds = new Set(candidates.map((c) => c.id));
  const valid: LlmPick[] = [];
  for (const s of stops) {
    if (s && typeof s === "object" && candidateIds.has(s.location_id)) {
      // Safely capture the reason
      s.reason = s.reason ?? "";
      valid.push(s);
    }
  }

  const target = wantedVisits ?? 8;
  // If the LLM somehow didn't select enough, pad with top available candidates
  if (valid.length < target) {
    const validIds = new Set(valid.map((s) => s.location_id));
    for (const c of candidates) {
      if (!validIds.has(c.id)) {
        valid.push({ location_id: c.id, reason: "A great addition to your route." });
        validIds.add(c.id);
      }
      if (valid.length >= target) break;
    }
  }

  return valid.slice(0, target);
}

export interface BuildCandidatesOptions {
  skipIds?: ReadonlySet<string>;
  limit?: number;
  prompt?: string;
}

/**
 * Ranked POI candidates around a point, from Overpass.
 *
 * The single source of candidates for both `/api/itinerary` and
 * `/api/itinerary/modify`. They used to disagree, and not harmlessly:
 * generate built `osm-{type}-{id}` candidates from Overpass, while modify
 * queried the `locations` table for uuid-keyed rows. So the ids the client
 * sent back in `existing_stops` — all `osm-*`, since that is what generate
 * returned — never appeared in modify's candidate set, `candidateIds`
 * rejected every one of them, and "keep the stops you already have" was
 * unrepresentable. Every modify silently replaced the whole route with
 * catalogue rows, and once the catalogue was empty, with the curated 8.
 *
 * Rejected/accepted ids are filtered before the trim rather than after, so
 * a swiped-away stop no longer consumes one of the `limit` slots.
 */
async function buildCandidates(
  lat: number,
  lng: number,
  radiusKm: number,
  options: BuildCandidatesOptions = {},
): Promise<Candidate[]> {
  const { skipIds = new Set<string>(), limit = CANDIDATE_LIMIT, prompt = "" } = options;

  const searchRadius = Math.max(radiusKm, 15.0);
  const latDelta = searchRadius / 111.0;
  const lngDelta = searchRadius / (111.0 * Math.cos((lat * Math.PI) / 180));

  let rawPois;
  try {
    rawPois = await fetchPois(lat - latDelta, lng - lngDelta, lat + latDelta, lng + lngDelta);
  } catch (error) {
    // Overpass is a free shared service and it does go down. It has
    // already retried and already tried its own stale cache by this point,
    // so this is the last line before the user gets nothing — and getting
    // nothing is what a Tipaza request got when all three mirrors returned
    // 504 at the same moment. The catalogue is a worse answer than live
    // OSM but an incomparably better one than an empty route.
    logger.exception(`Overpass unavailable for (${lat}, ${lng}) — falling back to catalogue`, error);
    return catalogueCandidates(lat, lng, radiusKm, { skipIds, limit });
  }

  const candidates: Candidate[] = [];
  for (const poi of rawPois) {
    const candidateId = `osm-${poi.osm_type}-${poi.osm_id}`;
    if (skipIds.has(candidateId)) continue;
    const [score] = computeScore({
      category: poi.category,
      name: poi.name,
      osmTags: poi.tags,
      wikidataMatch: null,
      wikipediaFound: false,
      pageviews30d: null,
      hasPhoto: false,
    });
    if (score < 0) continue;
    candidates.push({
      id: candidateId,
      name: poi.name,
      category: poi.category,
      lat: poi.lat,
      lng: poi.lng,
      bounds: poi.bounds,
      tags: poi.tags,
      interest_score: score,
      wikipedia: poi.wikipedia,
      wikidata_qid: poi.wikidata_qid,
      distance_km: haversineKm(lat, lng, poi.lat, poi.lng),
      // `ingestion/describe.ts` exists precisely to replace the
      // "A {category} point of interest." template that used to be here,
      // and this path never called it — so every generated stop carried
      // a blurb like "A park point of interest." or "A ruins point of
      // interest.", which is what made the descriptions read as generic.
      // `useLlm: false` keeps it deterministic and free: this runs for
      // every candidate on the request path, where 50 LLM calls is not
      // a trade worth making.
      blurb: await describe(
        collectFacts({
          name: poi.name,
          category: poi.category,
          tags: poi.tags,
          place: poi.tags["addr:city"],
        }),
        { useLlm: false },
      ),
    });
  }

  return mergeByRelevance(candidates, searchRadius, prompt, limit);
}

/**
 * Rank, reserving room for what the traveller asked for.
 *
 * A single ranked sort with a relevance bonus does not work here, and the
 * measurement is unambiguous: "shopping malls" in Bab Ezzouar filled all 50
 * candidate slots with malls and markets, so the model's only possible
 * answer was eight shopping centres in a row. Too small a bonus and the
 * requested category never survives the trim at all — which is the bug this
 * started as.
 *
 * Neither is a ranking problem, so it isn't solved with a weight. The
 * requested category gets a guaranteed *share* of the list and the rest is
 * filled on merit, so asking for malls returns the malls plus the city's
 * actual landmarks, and the model chooses the mix.
 */
function mergeByRelevance(
  candidates: Candidate[],
  searchRadiusKm: number,
  prompt: string,
  limit: number,
): Candidate[] {
  const terms = promptTerms(prompt);
  const ranked = [...candidates].sort((a, b) => rank(b, searchRadiusKm) - rank(a, searchRadiusKm));
  if (terms.size === 0) {
    return ranked.slice(0, limit);
  }

  const matched = ranked.filter((c) => matchesPrompt(c, terms));
  const others = ranked.filter((c) => !matchesPrompt(c, terms));

  const reserved = Math.min(matched.length, Math.max(1, Math.trunc(limit * PROMPT_RESERVED_SHARE)));
  const out = matched.slice(0, reserved);
  const seen = new Set<Candidate>(out);
  for (const candidate of [...others, ...matched.slice(reserved)]) {
    if (out.length >= limit) break;
    if (!seen.has(candidate)) {
      out.push(candidate);
      seen.add(candidate);
    }
  }
  return out;
}

/**
 * What a stop at the very edge of the search radius gives up against one on
 * the doorstep. Roughly the gap between a wikidata-linked landmark and an
 * unremarkable park, so a real landmark across town still outranks filler
 * next door, but two comparable places sort near-first.
 */
const DISTANCE_PENALTY_AT_EDGE = 8.0;

/**
 * The share of the candidate list guaranteed to what the traveller asked for.
 * 40% of 50 leaves 30 slots for the area's actual landmarks, so a request for
 * malls yields malls *and* the Casbah rather than one or the other.
 */
const PROMPT_RESERVED_SHARE = 0.4;

/**
 * Distinctive words from the request, for matching against candidates.
 *
 * `[^\p{L}\p{N}_]+` rather than `[^\w]+`: JavaScript's `\w` is ASCII-only, so
 * the Python pattern would have split French and Arabic requests into rubble.
 */
function promptTerms(prompt: string): Set<string> {
  if (!prompt) return new Set();
  const split = prompt.toLowerCase().split(/[^\p{L}\p{N}_]+/u);
  const out = new Set<string>();
  for (const w of split) {
    if (w.length >= 4 && !PROMPT_STOPWORDS.has(w)) out.add(w);
  }
  return out;
}

/** Words that say nothing about *what* to visit and would match everything. */
const PROMPT_STOPWORDS = new Set([
  "want", "would", "like", "some", "something", "please", "with", "near",
  "nearby", "around", "visit", "visiting", "show", "find", "give", "take",
  "there", "that", "this", "then", "from", "into", "about", "have", "need",
  "really", "maybe", "just", "also", "more", "most", "very", "good", "nice",
  "place", "places", "area", "areas", "trip", "tour", "route", "stop",
  "stops", "day", "days", "time", "kind", "type", "thing", "things",
]);

/** Synonyms, so the traveller's word reaches the OSM category it means. */
const PROMPT_SYNONYMS: Record<string, string[]> = {
  mall: ["shopping mall"],
  malls: ["shopping mall"],
  shopping: ["shopping mall", "market"],
  shop: ["shopping mall", "market"],
  shops: ["shopping mall", "market"],
  souk: ["market"],
  market: ["market"],
  markets: ["market"],
  beach: ["beach", "beach resort"],
  beaches: ["beach", "beach resort"],
  museum: ["museum"],
  museums: ["museum"],
  mosque: ["mosque"],
  mosques: ["mosque"],
  church: ["church"],
  ruins: ["ruins", "archaeological site"],
  roman: ["ruins", "archaeological site"],
  history: ["heritage", "monument", "memorial", "castle", "fort", "ruins"],
  historic: ["heritage", "monument", "memorial", "castle", "fort", "ruins"],
  historical: ["heritage", "monument", "memorial", "castle", "fort", "ruins"],
  park: ["park", "garden"],
  parks: ["park", "garden"],
  garden: ["garden", "park"],
  gardens: ["garden", "park"],
  nature: ["park", "garden", "peak", "beach", "cave"],
  view: ["viewpoint", "peak"],
  views: ["viewpoint", "peak"],
  viewpoint: ["viewpoint", "peak"],
  theatre: ["theatre"],
  theater: ["theatre"],
  cinema: ["cinema"],
  art: ["arts centre", "artwork", "gallery", "museum"],
  food: ["market"],
  eat: ["market"],
};

/** Whether the traveller asked for this kind of place, by category or name. */
function matchesPrompt(candidate: Candidate, terms: ReadonlySet<string>): boolean {
  if (terms.size === 0) return false;
  const category = (candidate.category ?? "").toLowerCase();
  const name = (candidate.name ?? "").toLowerCase();
  for (const term of terms) {
    if (category.includes(term) || name.includes(term)) return true;
    if ((PROMPT_SYNONYMS[term] ?? []).includes(category)) return true;
  }
  return false;
}

/**
 * Interest, discounted by how far out of the way it is.
 *
 * The distance penalty is a fraction of the radius the user actually asked
 * for, not a flat 2 points per km. The flat version silently made the radius
 * setting meaningless: at 2/km, anything past ~5 km was outscored by
 * whatever park happened to be nearest, so asking for 50 km returned the
 * same handful of doorstep POIs as asking for 5.
 *
 * Relevance to the traveller's request is deliberately *not* folded in here
 * — see `mergeByRelevance`, which reserves list slots instead. A bonus
 * large enough to guarantee a requested category survives the trim is also
 * large enough to let it take every slot.
 */
function rank(candidate: Candidate, searchRadiusKm: number): number {
  const distance = candidate.distance_km ?? 0;
  const reach = Math.max(searchRadiusKm, 1.0);
  const penalty = DISTANCE_PENALTY_AT_EDGE * Math.min(distance / reach, 1.5);
  return (candidate.interest_score ?? 0) - penalty;
}

/**
 * Candidates from the `locations` catalogue, shaped like Overpass ones.
 *
 * Only used when live Overpass is unreachable. `locationsRepo` degrades
 * further on its own — to the curated seed set — so this returns a non-empty
 * list even against an empty catalogue, which is the whole point of it.
 */
async function catalogueCandidates(
  lat: number,
  lng: number,
  radiusKm: number,
  options: { skipIds?: ReadonlySet<string>; limit?: number } = {},
): Promise<Candidate[]> {
  const { skipIds = new Set<string>(), limit = CANDIDATE_LIMIT } = options;
  const rows = await locationsWithinRadius(lat, lng, radiusKm, { limit });
  const candidates: Candidate[] = [];
  for (const row of rows) {
    if (skipIds.has(row.id)) continue;
    candidates.push({
      id: row.id,
      name: row.name ?? "",
      category: row.category ?? "Attraction",
      lat: row.lat,
      lng: row.lng,
      tags: {},
      // Catalogue rows are pre-vetted at ingestion time, so they enter
      // at a flat baseline rather than being re-scored from tags they
      // no longer carry.
      interest_score: 20,
      wikipedia: null,
      wikidata_qid: null,
      region: row.region,
      distance_km: row.distance_km ?? haversineKm(lat, lng, row.lat, row.lng),
      blurb: row.blurb ?? "",
      photo_url: row.photo_url ?? null,
    });
  }
  return candidates.slice(0, limit);
}

/**
 * Whether `inner`'s position falls inside `outer`'s footprint.
 *
 * Only ways carry a footprint; a node has no extent, so it can contain
 * nothing. `outer === inner` is excluded so a stop never encloses itself.
 */
export function encloses(outer: Candidate, inner: Candidate): boolean {
  if (outer === inner) return false;
  const bounds = outer.bounds;
  if (!bounds) return false;
  return (
    bounds.minlat <= inner.lat &&
    inner.lat <= bounds.maxlat &&
    bounds.minlon <= inner.lng &&
    inner.lng <= bounds.maxlon
  );
}

/**
 * Keep at most one stop per enclosing site, then backfill.
 *
 * This is the "three cards for one place" fix. Tipaza's archaeological park
 * is a single 951 m way that contains the Roman theatre, the amphitheatre,
 * the Villa des Fresques, the nymphaeum and the site museum as separate OSM
 * ways. Each is a legitimately distinct object with its own Wikidata id, so
 * no name- or id-based rule treats them as duplicates — but a route that
 * spends three of its eight stops inside one park, on one ticket, reads as
 * duplicated to the person holding the phone, which is exactly how it was
 * reported.
 *
 * Note this is deliberately a *route* rule and not a catalogue rule. The
 * candidates all survive; only the itinerary is thinned. Size thresholds
 * were tried first and don't separate the cases — Tipaza's park is 951 m
 * across and the Casbah of Algiers is 1387 m, but the Casbah's contents
 * (Ketchaoua Mosque, Serkadji Prison) are independently worth their own
 * stop while Tipaza's are features of one visit. Capping at one stop per
 * enclosure gets both right without having to tell them apart.
 *
 * The enclosing site is the one kept: it is what you navigate to, and it
 * carries the name and the photograph.
 */
export function dropEnclosed(
  stops: Candidate[],
  candidates: Candidate[],
  wanted: number,
): Candidate[] {
  const kept: Candidate[] = [];
  for (const stop of stops) {
    if (stops.some((other) => other !== stop && encloses(other, stop))) {
      continue; // a larger selected stop already covers this one
    }
    kept.push(stop);
  }

  if (kept.length >= stops.length) {
    return kept;
  }

  // Backfill so a thinned route still offers a full day out.
  const chosenIds = new Set(kept.map((s) => s.id));
  for (const candidate of candidates) {
    if (kept.length >= wanted) break;
    if (chosenIds.has(candidate.id)) continue;
    if (kept.some((k) => encloses(k, candidate) || encloses(candidate, k))) continue;
    kept.push({ ...candidate, reason: "Added to round out your route." });
    chosenIds.add(candidate.id);
  }
  return kept;
}

/**
 * The photo fields for one candidate, or null. Never throws — a route
 * without a photo is fine, a route that failed because of one is not.
 *
 * Coordinates and name variants are passed, which turns on the
 * coordinate-anchored discovery tiers in `ingestion/photos.ts` (geotagged
 * Commons files, nearby Wikipedia articles, then Openverse). Without them
 * only the structured tiers ran, so a POI that OSM never linked to Wikidata
 * or Wikipedia could never get a photo at all — and that is most of them:
 * 4 of 12 Tipaza candidates resolved an image, the other 8 showed the
 * placeholder.
 *
 * Those tiers are several more HTTP round trips, which is affordable only
 * because this now runs prefetched underneath the LLM call rather than
 * after it, under `PHOTO_WAIT_S`.
 */
async function photoFor(candidate: Candidate): Promise<PhotoFields | null> {
  try {
    let wiki = candidate.wikipedia ?? null;
    if (wiki && wiki.includes(":")) {
      wiki = wiki.slice(wiki.indexOf(":") + 1);
    }
    const tags = candidate.tags ?? {};
    const exact = await resolvePhoto({
      wikipediaTitle: wiki,
      wikidataImageFilename: null,
      osmTags: { name: candidate.name ?? "", ...tags },
      wikidataQid: candidate.wikidata_qid ?? null,
      name: candidate.name,
      lat: candidate.lat,
      lng: candidate.lng,
      // The containing city, which the Openverse tier needs to tell this
      // place from a same-named one on another continent, and which the
      // other tiers use to stop a city name alone counting as a match.
      placeContext:
        tags["addr:city"] ?? tags["addr:province"] ?? (candidate.region as string | undefined) ?? null,
    });
    if (exact) {
      return { ...exact, photo_is_stock: false };
    }

    // Nothing depicting this place exists that we can verify. Rather than
    // the empty placeholder, offer a real photograph of the surroundings
    // and mark it — see `resolveNearbyPhoto`, and note the client shows
    // a "Nearby photo" chip so this is never passed off as the subject.
    if (candidate.lat !== null && candidate.lat !== undefined && candidate.lng !== null && candidate.lng !== undefined) {
      return await resolveNearbyPhoto({ lat: candidate.lat, lng: candidate.lng });
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * The opening of this place's own Wikipedia article, if it has one.
 *
 * The OSM-derived description is honest but thin — "A mall.", "A
 * marketplace." — because it may only state what the tags state. Where a
 * Wikipedia article exists, its first sentences are real, sourced prose
 * about this specific place, which is what the cards were missing.
 */
async function wikipediaBlurb(candidate: Candidate): Promise<string | null> {
  const wiki = candidate.wikipedia;
  if (!wiki) return null;
  const tags = candidate.tags ?? {};

  let lang: string;
  let title: string;
  if (wiki.includes(":")) {
    const idx = wiki.indexOf(":");
    lang = wiki.slice(0, idx) || "en";
    title = wiki.slice(idx + 1) || wiki;
  } else {
    lang = "en";
    title = wiki;
  }

  // English first, whatever language OSM happened to tag. The `wikipedia`
  // tag on Algerian POIs is as often `fr:` or `ar:` as `en:`, and taking it
  // at face value put a French paragraph on the Bab Ezzouar mall card and an
  // Arabic one on Riadh El Feth — correct, sourced, and unreadable to
  // someone using the app in English.
  const attempts: Array<[string, string]> = [];
  const englishTag = tags["wikipedia:en"];
  if (englishTag) {
    const idx = englishTag.indexOf(":");
    attempts.push(["en", (idx === -1 ? "" : englishTag.slice(idx + 1)) || englishTag]);
  }
  if (lang === "en") {
    attempts.push(["en", title]);
  } else {
    const englishName = tags["name:en"];
    if (englishName) {
      attempts.push(["en", englishName]);
    }
    // The tagged article last: real prose in the wrong language still
    // beats "A marketplace."
    attempts.push([lang, title]);
  }

  let extract: string | null = null;
  for (const [attemptLang, attemptTitle] of attempts) {
    let summary;
    try {
      summary = await fetchSummary(attemptTitle, attemptLang);
    } catch {
      continue;
    }
    extract = summary?.extract ?? null;
    if (extract) break;
  }
  if (!extract) return null;

  extract = collapseWhitespace(extract);
  if (extract.length <= BLURB_MAX_CHARS) {
    return extract;
  }
  // Cut on a sentence boundary so the card never ends mid-clause.
  const cut = extract.slice(0, BLURB_MAX_CHARS);
  const stop = Math.max(cut.lastIndexOf(". "), cut.lastIndexOf("! "), cut.lastIndexOf("? "));
  return stop > 80 ? cut.slice(0, stop + 1) : `${cut.replace(/\s+$/u, "")}…`;
}

/**
 * Attach photos and order the route.
 *
 * The two are independent — ordering reads only coordinates — so the OSRM
 * round trip runs concurrently with whatever photo lookups are still in
 * flight instead of after them. Photo waiting is bounded: a slow Commons or
 * Openverse tier delays a thumbnail, and must not delay the route.
 */
async function finalizeStops(
  startLat: number,
  startLng: number,
  stops: Candidate[],
  photoFutures: Map<string, PhotoFuture>,
  submit: <T>(fn: () => Promise<T>) => Promise<T>,
): Promise<Candidate[]> {
  if (stops.length === 0) {
    return [];
  }

  // Started outside the photo limiter, not inside it: queued there it would
  // wait behind up to PHOTO_PREFETCH photo tasks and lose the overlap entirely.
  const orderPromise = orderTravelTime(startLat, startLng, stops);

  // Only the chosen stops get a Wikipedia lookup — eight requests, in
  // parallel, for the eight cards the traveller will actually read.
  const blurbFutures = new Map<string, Promise<string | null>>();
  for (const s of stops) {
    if (s.wikipedia) {
      blurbFutures.set(
        s.id,
        submit(() => wikipediaBlurb(s)).catch(() => null),
      );
    }
  }

  for (const stop of stops) {
    // A stop carried over from an existing route already has its
    // photo; re-resolving it would spend the same round trips to
    // arrive at the same URL, or worse, at null.
    if (stop.photo_url || photoFutures.has(stop.id)) continue;
    // Picked from outside the prefetched slice — fetch it now.
    photoFutures.set(
      stop.id,
      submit(() => photoFor(stop)).catch(() => null),
    );
  }

  const photos = new Map<string, PhotoFields | null>();
  const deadline = new Deadline(PHOTO_WAIT_S * 1000);
  for (const stop of stops) {
    const future = photoFutures.get(stop.id);
    if (future === undefined) continue;
    photos.set(stop.id, await awaitWithin(future, deadline.remainingMs()));
  }

  const ordered = await orderPromise;

  for (const stop of ordered) {
    const photo = photos.get(stop.id);
    if (photo) {
      Object.assign(stop, photo);
    }
    if (stop.photo_is_stock === undefined) {
      stop.photo_is_stock = false;
    }

    const future = blurbFutures.get(stop.id);
    if (future !== undefined) {
      const better = await awaitWithin(future, deadline.remainingMs());
      if (better) {
        stop.blurb = better;
      }
    }
  }
  return ordered;
}

/**
 * Map extracted themes (`llm.extractIntent`) to OSM categories.
 *
 * Not currently called: category filtering was designed for the catalogue's
 * `nearby_locations(p_categories => ...)` argument, and candidates now come
 * from Overpass. Kept because it is the ready-made half of theme-aware
 * filtering over `buildCandidates` — wire it in there when the ranking
 * needs it, rather than rewriting the mapping.
 */
export function expandCategories(intent: Intent): string[] {
  const rules: Record<string, string[]> = {
    nature: ["Beach", "Peak", "Park", "Waterfall", "Bay", "Cape", "Cliff", "Spring", "Glacier", "Volcano"],
    history: ["Historic", "Ruins", "Monument", "Castle", "Fort", "Archaeological"],
    culture: ["Museum", "Art Gallery", "Theatre", "Mosque", "Church", "Library", "Artwork"],
    food: ["Market", "Restaurant", "Cafe", "Street food", "Bakery"],
    attraction: ["Attraction", "Theme park", "Zoo", "Aquarium", "Viewpoint"],
  };

  const categories = new Set<string>([
    ...(intent.required_categories ?? []),
    ...(intent.preferred_categories ?? []),
  ]);

  for (const theme of intent.themes ?? []) {
    const name = (theme.name ?? "").toLowerCase();
    for (const [k, v] of Object.entries(rules)) {
      if (name.includes(k) || k.includes(name)) {
        for (const category of v) categories.add(category);
      }
    }
  }

  return [...categories];
}

/** The pure ranking rules, exposed for the parity harness. See photos.ts. */
export const internals = {
  promptTerms: (prompt: string) => promptTerms(prompt),
  matchesPrompt: (candidate: Candidate, terms: ReadonlySet<string>) =>
    matchesPrompt(candidate, terms),
  rank: (candidate: Candidate, searchRadiusKm: number) => rank(candidate, searchRadiusKm),
  mergeByRelevance: (
    candidates: Candidate[],
    searchRadiusKm: number,
    prompt: string,
    limit: number,
  ) => mergeByRelevance(candidates, searchRadiusKm, prompt, limit),
  orderNearestNeighbor: (lat: number, lng: number, stops: Candidate[]) =>
    orderNearestNeighbor(lat, lng, stops),
};

/** Python's `min(int(x), cap)` with its TypeError/ValueError fallback to null. */
function clampWantedVisits(raw: unknown): number | null {
  if (raw === null || raw === undefined) return null;
  const parsed = Number.parseInt(String(raw), 10);
  if (Number.isNaN(parsed)) return null;
  return Math.min(parsed, MAX_WANTED_VISITS);
}

itineraryRouter.post(
  "/api/itinerary",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "generate_itinerary", 30, "1 hour");
    if (auth.failure) {
      return res.status(auth.failure.status).json(auth.failure.body);
    }
    const user = auth.user;

    const body = (req.body ?? {}) as Record<string, unknown>;

    const lat = Number(body.lat);
    const lng = Number(body.lng);
    if (body.lat === undefined || body.lng === undefined || !Number.isFinite(lat) || !Number.isFinite(lng)) {
      return res
        .status(400)
        .json({ error: "bad_request", message: "lat and lng are required numbers" });
    }

    if (!(lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180)) {
      return res.status(400).json({ error: "bad_request", message: "lat/lng out of range" });
    }

    const admin = getAdminClient();
    let jobId: string;
    try {
      // `.select()` is required for supabase-js to return the inserted row.
      const jobRows = await unwrapRows<{ id: string }>(
        admin
          .from("route_jobs")
          .insert({ user_id: user.id, request_params: body, status: "queued" })
          .select("id"),
      );
      if (jobRows.length === 0) {
        return res.status(500).json({ error: "server_error", message: "Could not create job" });
      }
      jobId = jobRows[0].id;
    } catch (error) {
      return res
        .status(500)
        .json({ error: "server_error", message: error instanceof Error ? error.message : String(error) });
    }

    const processJob = async (): Promise<void> => {
      try {
        const radiusKm = Math.min(Number(body.radius_km ?? 20), MAX_RADIUS_KM);
        await unwrap(admin.from("route_jobs").update({ status: "processing" }).eq("id", jobId));

        // Step 2: Route Generation
        const prompt = String(body.prompt ?? "").trim().slice(0, 500);
        const wantedVisits = clampWantedVisits(body.wanted_visits);

        const rejectedIds = Array.isArray(body.rejected_ids) ? body.rejected_ids : [];
        const acceptedIds = Array.isArray(body.accepted_ids) ? body.accepted_ids : [];

        let candidates: Candidate[];
        try {
          candidates = await buildCandidates(lat, lng, radiusKm, {
            skipIds: new Set([...rejectedIds, ...acceptedIds].map(String)),
            prompt,
          });
        } catch (error) {
          await unwrap(
            admin
              .from("route_jobs")
              .update({
                status: "failed",
                error_message: `Overpass error: ${error instanceof Error ? error.message : error}`,
              })
              .eq("id", jobId),
          );
          return;
        }

        const existingStops = Array.isArray(body.existing_stops)
          ? (body.existing_stops as Array<Record<string, unknown>>)
          : [];

        // Start photo lookups now, against the ranked list, so they run
        // underneath the LLM call instead of after it. The picks come out
        // of the top of this same list, so by the time selection returns
        // most of what's needed is already resolved.
        const submit = createLimiter(PHOTO_CONCURRENCY);
        const photoFutures = new Map<string, PhotoFuture>(
          candidates.slice(0, PHOTO_PREFETCH).map((c) => [
            c.id,
            submit(() => photoFor(c)).catch(() => null),
          ]),
        );

        let hydrated: Candidate[];
        if (!prompt && existingStops.length === 0) {
          hydrated = candidates
            .slice(0, Math.min(8, candidates.length))
            .map((c) => ({ ...c, reason: "One of the closer highlights to your starting point." }));
        } else {
          try {
            const picked = await selectWithLlm(
              candidates.slice(0, LLM_CANDIDATE_LIMIT),
              prompt,
              8,
              existingStops,
            );
            const byId = new Map(candidates.map((c) => [c.id, c]));
            hydrated = picked
              .filter((s) => byId.has(s.location_id))
              .map((s) => ({ ...(byId.get(s.location_id) as Candidate), reason: s.reason ?? "" }));
          } catch (error) {
            logger.exception("LLM generation failed", error);
            throw new Error(`llm_error: ${error instanceof Error ? error.message : error}`);
          }
        }

        hydrated = dropEnclosed(hydrated, candidates, 8);
        const stopsOut = await finalizeStops(lat, lng, hydrated, photoFutures, submit);

        await unwrap(
          admin
            .from("route_jobs")
            .update({ status: "succeeded", result_data: { stops: stopsOut } })
            .eq("id", jobId),
        );
      } catch (error) {
        await unwrap(
          admin
            .from("route_jobs")
            .update({
              status: "failed",
              error_message: error instanceof Error ? error.message : String(error),
            })
            .eq("id", jobId),
        ).catch((inner) => logger.exception(`Could not mark job ${jobId} as failed`, inner));
      }
      // No pool to shut down: the prefetches for candidates that weren't
      // picked resolve on their own and are never awaited.
    };

    // Fire and forget, exactly as the Python's `threading.Thread(...).start()`
    // did — with the same caveat that a process restart loses the job.
    void processJob();

    return res.json({ job_id: jobId });
  }),
);

itineraryRouter.get(
  "/api/itinerary/job/latest",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "get_job", 1000, "1 hour");
    if (auth.failure) {
      return res.status(auth.failure.status).json(auth.failure.body);
    }

    const admin = getAdminClient();
    const rows = await unwrapRows<Record<string, unknown>>(
      admin
        .from("route_jobs")
        .select("*")
        .eq("user_id", auth.user.id)
        .order("created_at", { ascending: false })
        .limit(1),
    );
    if (rows.length === 0) {
      return res.json({ job: null });
    }

    return res.json({ job: rows[0] });
  }),
);

itineraryRouter.get(
  "/api/itinerary/job/:jobId",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "get_job", 1000, "1 hour");
    if (auth.failure) {
      return res.status(auth.failure.status).json(auth.failure.body);
    }

    const admin = getAdminClient();
    const jobId = req.params.jobId;

    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const rows = await unwrapRows<Record<string, unknown>>(
          admin.from("route_jobs").select("*").eq("id", jobId).eq("user_id", auth.user.id),
        );
        if (rows.length === 0) {
          return res.status(404).json({ error: "not_found" });
        }
        return res.json(rows[0]);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (
          message.includes("10035") ||
          message.includes("ReadError") ||
          message.toLowerCase().includes("timeout")
        ) {
          await sleep(1000);
          continue;
        }
        return res.status(500).json({ error: "server_error", message });
      }
    }

    return res.status(500).json({ error: "server_error", message: "Database query timed out" });
  }),
);

/**
 * Modify an existing itinerary based on a user's change request
 * (SendAIChangeEvent).
 *
 * The key invariant: every location_id in the response must come from the same
 * candidate set the original itinerary was built from — the LLM cannot
 * promote a location it invented or that scores below the floor. That is why
 * this now calls `buildCandidates`, exactly as `/api/itinerary` does,
 * instead of the `locations` catalogue: "the same candidate set" was the
 * stated invariant but not the implemented one.
 *
 * Body:
 *   lat, lng          (float, required) — user's original departure point
 *   radius_km         (float, optional, default 20) — search radius
 *   existing_stops    (list[{id, name, lat, lng, ...}], required) — the current route
 *   change_request    (str, required) — e.g. "add something with Roman ruins"
 */
itineraryRouter.post(
  "/api/itinerary/modify",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "modify_itinerary", 60, "1 hour");
    if (auth.failure) {
      return res.status(auth.failure.status).json(auth.failure.body);
    }

    const body = (req.body ?? {}) as Record<string, unknown>;

    const lat = Number(body.lat);
    const lng = Number(body.lng);
    if (body.lat === undefined || body.lng === undefined || !Number.isFinite(lat) || !Number.isFinite(lng)) {
      return res
        .status(400)
        .json({ error: "bad_request", message: "lat and lng are required numbers" });
    }

    if (!(lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180)) {
      return res.status(400).json({ error: "bad_request", message: "lat/lng out of range" });
    }

    const existingStops = body.existing_stops;
    if (!Array.isArray(existingStops) || existingStops.length === 0) {
      return res
        .status(400)
        .json({ error: "bad_request", message: "existing_stops must be a non-empty list" });
    }

    const changeRequest = String(body.change_request ?? "").trim().slice(0, 500);
    if (!changeRequest) {
      return res.status(400).json({ error: "bad_request", message: "change_request is required" });
    }

    const radiusKm = Math.min(Number(body.radius_km ?? 20), MAX_RADIUS_KM);
    const wantedVisits = clampWantedVisits(body.wanted_visits);

    // No `embed()` call here any more: its only consumer was the
    // `nearby_locations` RPC's semantic ranking, so with the catalogue out of
    // this path it was a Gemini round trip whose result was discarded — pure
    // latency on a request the user is watching.
    let candidates: Candidate[];
    try {
      candidates = await buildCandidates(lat, lng, radiusKm, { prompt: changeRequest });
    } catch (error) {
      return res.status(503).json({
        error: "upstream_unavailable",
        message: error instanceof Error ? error.message : String(error),
      });
    }

    // The current stops must themselves be selectable, or "keep the ones I
    // have" cannot be expressed: the model can only answer with ids, and a
    // stop absent from the candidate list has no id to name it by. Overpass
    // normally returns them (they came from it), but a stop just outside a
    // narrowed radius would otherwise be silently undroppable-or-keepable.
    const byId = new Map<string, Candidate>(candidates.map((c) => [c.id, c]));
    const readopted: Candidate[] = [];
    for (const rawStop of existingStops as Array<Record<string, unknown>>) {
      const stopId = rawStop.id as string | undefined;
      if (!stopId) continue;
      const known = byId.get(stopId);
      if (known) {
        // Already a candidate. Carry over the photo the client is
        // currently displaying, so a stop the user chose to keep doesn't
        // silently change its image — and so `finalizeStops` doesn't
        // spend a lookup rediscovering it.
        if (rawStop.photo_url && !known.photo_url) {
          known.photo_url = rawStop.photo_url as string;
        }
        continue;
      }
      if (rawStop.lat === null || rawStop.lat === undefined || rawStop.lng === null || rawStop.lng === undefined) {
        // Pre-existing clients sent only {id, name}; without coordinates
        // it cannot be ordered, so it can't be offered as a candidate.
        continue;
      }
      const merged = { ...rawStop } as Candidate;
      merged.category = merged.category ?? "Attraction";
      merged.blurb = merged.blurb ?? "";
      merged.tags = merged.tags ?? {};
      merged.distance_km =
        merged.distance_km ?? haversineKm(lat, lng, Number(rawStop.lat), Number(rawStop.lng));
      byId.set(stopId, merged);
      readopted.push(merged);
    }

    // Current stops go at the head of the offered list, never into the tail
    // that the LLM_CANDIDATE_LIMIT trim discards — otherwise re-adding them as
    // candidates would be undone by the trim for exactly the routes that
    // needed it.
    const offered = [...readopted, ...candidates.slice(0, LLM_CANDIDATE_LIMIT)];

    // Build a modify-specific prompt that names existing stops explicitly
    const existingNames = (existingStops as Array<Record<string, unknown>>).map(
      (s) => (s.name as string | undefined) ?? "Unknown",
    );
    const candidateLines = offered.map(candidateLine).join("\n");
    const visitsLine = wantedVisits
      ? `The new route should have about ${wantedVisits} stops.`
      : `Keep a similar number of stops (${existingStops.length}) unless the request says otherwise.`;

    const messages: ChatMessage[] = [
      {
        role: "system",
        content:
          "You are adjusting a walking/driving tour in Algeria. " +
          "The traveller has an existing route and wants to change it. " +
          "Choose ONLY from the provided candidate locations — never invent a place. " +
          'Reply with a single JSON object shaped exactly like: {"stops": [{"location_id": "...", ' +
          '"reason": "one sentence, addressed to the traveller", ' +
          '"suggested_order": 0}]}. No prose outside the JSON.',
      },
      {
        role: "user",
        content:
          `Current route: ${existingNames.join(", ")}\n` +
          `Change request: "${changeRequest}"\n` +
          `${visitsLine}\n\n` +
          `Available candidates (include current stops if you keep them):\n${candidateLines}`,
      },
    ];

    let raw: string;
    try {
      // Same shape of task as the initial selection, and just as much on the
      // user's waiting path — the AI prompt bar blocks on this response.
      raw = await chat(messages, {
        jsonMode: true,
        maxTokens: 1024,
        temperature: 0.6,
        thinkingLevel: "minimal",
        prefer: "groq",
      });
    } catch (error) {
      if (error instanceof LLMError) {
        return res.status(503).json({ error: "llm_unavailable", message: error.message });
      }
      throw error;
    }

    let stops: LlmPick[];
    try {
      const parsed = extractJson(raw);
      if (!Array.isArray(parsed.stops)) {
        throw new JsonExtractionError("LLM response had no 'stops' array");
      }
      stops = parsed.stops as LlmPick[];
    } catch (error) {
      return res.status(502).json({
        error: "llm_bad_output",
        message: error instanceof Error ? error.message : String(error),
      });
    }

    // Enforce: only ids from the verified candidate set survive. `byId` is
    // the set actually offered plus the re-adopted current stops, so keeping
    // an existing stop is now a valid answer.
    const validPicks = stops.filter(
      (s) => s && typeof s === "object" && byId.has(s.location_id),
    );

    if (validPicks.length === 0) {
      return res
        .status(200)
        .json({ error: "no_matches", message: "No candidates matched that change request" });
    }

    const hydrated = validPicks.map((s) => ({
      ...(byId.get(s.location_id) as Candidate),
      reason: s.reason ?? "",
    }));

    // Photos and ordering on the same concurrent path the generate route uses.
    // Stops carried over from the current route already have their photo_url
    // and keep it — `finalizeStops` only overwrites on a positive lookup.
    const submit = createLimiter(PHOTO_CONCURRENCY);
    const photoFutures = new Map<string, PhotoFuture>();
    for (const s of hydrated) {
      if (!s.photo_url) {
        photoFutures.set(
          s.id,
          submit(() => photoFor(s)).catch(() => null),
        );
      }
    }
    const ordered = await finalizeStops(lat, lng, hydrated, photoFutures, submit);

    return res.json({ stops: ordered });
  }),
);

itineraryRouter.post(
  "/api/itinerary/accept",
  asyncHandler(async (req, res) => {
    const auth = await authenticateAndRateLimit(req, "accept_itinerary", 100, "1 hour");
    if (auth.failure) {
      return res.status(auth.failure.status).json(auth.failure.body);
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    const jobId = body.job_id;
    const acceptedStops = body.accepted_stops;
    if (!jobId || !Array.isArray(acceptedStops)) {
      return res.status(400).json({ error: "bad_request" });
    }

    const admin = getAdminClient();
    try {
      await unwrap(
        admin
          .from("route_jobs")
          .update({ status: "accepted", result_data: { stops: acceptedStops } })
          .eq("id", jobId)
          .eq("user_id", auth.user.id),
      );
      return res.json({ success: true });
    } catch (error) {
      return res.status(500).json({
        error: "server_error",
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }),
);
