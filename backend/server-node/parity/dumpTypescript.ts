/**
 * Emit the *TypeScript* implementation's answers for the same corpus, as JSON.
 *
 * The other half of the differential parity check. Run from
 * `backend/server-node`:
 *
 *     npx tsx parity/dumpTypescript.ts > /tmp/ts.json
 *
 * Keep the corpus in this file and `dumpPython.py` byte-identical when adding
 * cases — a case present in only one of them silently proves nothing.
 */
import {
  categoryFromTags, isExcluded, isRealName, nameVariants, internals as ovi,
} from "../src/ingestion/overpass";
import { internals as phi } from "../src/ingestion/photos";
import { computeScore } from "../src/ingestion/scoring";
import { collectFacts, compose } from "../src/ingestion/describe";
import { internals as iti } from "../src/routes/itinerary";
import { coveringTiles, tileBounds, tileIdFor } from "../src/ingestion/tiling";
import { haversineKm } from "../src/data/geo";
import { normalizeFold, roundTo } from "../src/text";
import { Candidate, HeritageStatus, OsmTags } from "../src/types";

const STRINGS = [
  "ÎLOT 661", "ilot 661", "Sidi M'Cid", "مقام الشهيد", "أحمد", "قلعة", "Café Malakoff",
  "Mémorial du martyr", "Djenane El Mithak (Résidence d'Etat)", "Bab Azzoun", "114pa466551",
  "Ne", "214145", "Route 66", "Place du 1er Novembre", "Martyrs Memorial 2", "Dar Aziza;Palais",
  "Ketchaoua Mosque architecture – Algiers 8.jpg", "Streets in Algiers 2024 06.jpg",
  "Mosquée du Dey (Alger)", "تمثال الامير عبد القادر", "  spaced   out  ", "",
  "Timgad", "Tassili n'Ajjer", "Yemma Gouraya", "Ambassade du Brésil", "ÉCOLE", "ЖУРНАЛ",
  "no 2", "Parc 12", "Parc n 3", "Beb El Bhar", "Bir Jebah", "Kilometre Zero", "９９",
];

const TAGSETS: OsmTags[] = [
  { historic: "yes", amenity: "place_of_worship", religion: "muslim" },
  { historic: "heritage", amenity: "place_of_worship", religion: "muslim", building: "mosque" },
  { historic: "castle", castle_type: "palace" },
  { historic: "castle", castle_type: "hill" },
  { historic: "castle", castle_type: "stately" },
  { historic: "yes" },
  { historic: "building" },
  { office: "diplomatic", diplomatic: "embassy", embassy: "yes", leisure: "park", barrier: "wall" },
  { historic: "fort", military: "bunker" },
  { military: "barracks", tourism: "attraction" },
  { barrier: "wall", tourism: "museum", wikidata: "Q3403985" },
  { leisure: "park" }, { leisure: "garden" }, { leisure: "water_park" }, { leisure: "stadium" },
  { natural: "peak" }, { natural: "cave_entrance" }, { natural: "arch" }, { natural: "fjord" },
  { waterway: "waterfall" }, { shop: "mall" }, { amenity: "marketplace" }, { amenity: "cinema" },
  { amenity: "place_of_worship" }, { amenity: "place_of_worship", building: "cathedral" },
  { amenity: "place_of_worship", religion: "zoroastrian" },
  { tourism: "attraction" }, { tourism: "hotel" }, { tourism: "yes" }, { tourism: "artwork" },
  { landuse: "industrial" }, { landuse: "military" }, { amenity: "parking" },
  { barrier: "wall", leisure: "park" },
  { barrier: "fence", leisure: "park", access: "permissive" },
  { barrier: "wall", leisure: "park", wikidata: "Q123" },
  { man_made: "lighthouse" }, { building: "yes" }, { memorial: "statue" },
  { historic: "memorial", name: "Martyrs Memorial", "name:fr": "Mémorial", "name:ar": "مقام الشهيد", wikidata: "Q3056085" },
  { tourism: "viewpoint", name: "مقام الشهيد", "name:en": "Martyrs Memorial" },
  { amenity: "place_of_worship", religion: "muslim", denomination: "sunni", start_date: "1612", operator: "Ministry" },
  { office: "diplomatic", country: "fr" }, { office: "diplomatic", country: "zz" },
  { office: "diplomatic" }, { access: "private", leisure: "park" },
  { website: "x", opening_hours: "y", description: "z", image: "w", leisure: "park" },
  { "description:en": "A genuinely explicit description of this place, long enough." },
  { description: "short" },
];

const NAMES_FOR_SCORE = [
  "Villa Montfeld", "Hamma Park", "Dar Aziza", "Djenane El Mithak (Résidence d'Etat)",
  "Ambassade du Brésil", "Jardin d'Essai", "Parking Centre", "Public Toilets",
  "Consulate General", "Chancellerie", "Snack Bar", "Ticket Office", "Casbah of Algiers",
  "Résidence d'Etat", "RESIDENCE D ETAT", "gift shop", "Giftshop",
];

const PROMPTS = [
  "shopping malls", "I would like to visit some Roman ruins near Algiers",
  "musées et jardins", "شواطئ", "beaches and viewpoints", "history", "", "art",
  "show me nice places", "théâtre", "café", "old town walking tour",
];

const CANDIDATES_FOR_PROMPT = [
  { category: "Shopping mall", name: "Bab Ezzouar Mall" },
  { category: "Market", name: "Souk El Fellah" },
  { category: "Ruins", name: "Tipaza" },
  { category: "Museum", name: "Musée National" },
  { category: "Beach", name: "Chenoua Plage" },
  { category: "Park", name: "Jardin d'Essai" },
  { category: "Theatre", name: "Théâtre National" },
  { category: "Mosque", name: "Ketchaoua" },
] as unknown as Candidate[];

const PHOTO_CASES: Array<[string, string[], OsmTags, string]> = [
  ["Ketchaoua Mosque architecture – Algiers 8.jpg", ["Ketchaoua Mosque"], { "addr:city": "Algiers" }, "Algiers"],
  ["Streets in Algiers 2024 06.jpg", ["Museum of Modern Art of Algiers"], { "addr:city": "Algiers" }, "Algiers"],
  ["Mausolée de Sidi Abderrahmane ben Mohamed ben Makhlouf.jpg", ["Sidi Mohamed Sharif Mosque"], {}, "Algiers"],
  ["Publicité pour la marque de soda Crush, rue Bab Azzoun à Alger.jpg", ["Bab Azzoun"], {}, "Alger"],
  ["Rue Bab Azzoun.jpg", ["Rue Bab Azzoun"], {}, "Alger"],
  ["Mosquée du Dey (Alger).jpg", ["Palace of the Dey", "Mosquée du Dey"], {}, "Alger"],
  ["تمثال الامير عبد القادر.jpg", ["تمثال الأمير عبد القادر"], {}, "الجزائر"],
  ["#algiers #alger #algeria #casbah #oldcity #palais #palace #dey", ["Palace of the Dey"], {}, "Algiers"],
  ["Voiture ancienne alger.jpg", ["Beb El Bhar"], {}, "Alger"],
  ["Timgad Trajan Arch.jpg", ["Timgad"], { "addr:city": "Batna" }, "Batna"],
];

const out: Record<string, unknown> = {};

const obj = <T>(keys: string[], fn: (k: string) => T): Record<string, T> =>
  Object.fromEntries(keys.map((k) => [k, fn(k)]));

out.normalize = obj(STRINGS, (s) => normalizeFold(s));
out.photos_normalize = obj(STRINGS, (s) => normalizeFold(s));
out.is_real_name = obj(STRINGS, (s) => isRealName(s));
out.clean = obj(["cave_entrance", "yes", "RUINS", "city_gate", "a"], (s) => ovi.clean(s));
out.category = TAGSETS.map((t) => categoryFromTags(t));
out.excluded = TAGSETS.map((t) => isExcluded(t));
out.name_variants = TAGSETS.map((t) => [...nameVariants(t)].sort());

const score: unknown[] = [];
for (const name of NAMES_FOR_SCORE) {
  for (const tags of TAGSETS.slice(0, 20)) {
    const [total, bd] = computeScore({
      category: categoryFromTags(tags) ?? "Attraction", name, osmTags: tags,
      wikidataMatch: null, wikipediaFound: false, pageviews30d: null, hasPhoto: false,
    });
    score.push([roundTo(total, 6), Object.fromEntries(Object.entries(bd).map(([k, v]) => [k, roundTo(v, 6)]))]);
  }
}
out.score = score;

out.score_pageviews = [1, 30, 300, 3000, 30000, 300000, 3000000].map((pv) => {
  const [total, bd] = computeScore({
    category: "Museum", name: "X", osmTags: { historic: "castle" },
    wikidataMatch: { is_unesco: false, has_heritage: true, sitelinks: 5 } as never,
    wikipediaFound: true, pageviews30d: pv, hasPhoto: true,
  });
  return [roundTo(total, 6), Object.fromEntries(Object.entries(bd).map(([k, v]) => [k, roundTo(v, 6)]))];
});

const composed: unknown[] = [];
for (const tags of TAGSETS) {
  for (const hs of [null, "unesco_world_heritage", "heritage_listed"] as HeritageStatus[]) {
    const facts = collectFacts({
      name: "Test Place", category: categoryFromTags(tags) ?? "Attraction",
      tags, heritageStatus: hs, place: "Algiers",
    });
    composed.push([facts.kind, facts.embassy, facts.qualifiers, compose(facts)]);
  }
}
out.compose = composed;

out.prompt_terms = obj(PROMPTS, (p) => [...iti.promptTerms(p)].sort());
out.matches_prompt = PROMPTS.map((p) => {
  const terms = iti.promptTerms(p);
  return CANDIDATES_FOR_PROMPT.map((c) => iti.matchesPrompt(c, terms));
});

const ranks: number[] = [];
for (const d of [0, 1, 5, 20, 100, 1000]) {
  for (const s of [0, 25, 60]) {
    for (const r of [1, 15, 50, 500]) {
      ranks.push(roundTo(iti.rank({ distance_km: d, interest_score: s } as Candidate, r), 9));
    }
  }
}
out.rank = ranks;

const photoTokens: unknown[] = [];
const photoMatches: unknown[] = [];
for (const [candidate, names, tags, place] of PHOTO_CASES) {
  const stop = phi.placeStopwords(tags, place);
  const vt = names.map((n) => phi.tokens(n, stop)).filter((t) => t.size > 0);
  photoTokens.push([[...stop].sort(), vt.map((t) => [...t].sort()), [...phi.tokens(candidate, stop)].sort()]);
  photoMatches.push(vt.length > 0 ? phi.matchesSubject(candidate, vt, stop) : null);
}
out.photo_tokens = photoTokens;
out.photo_matches = photoMatches;

out.tag_dump = PHOTO_CASES.map(([c]) => phi.isTagDump(c));
out.photos_name_variants = PHOTO_CASES.map(([, n, t]) => phi.nameVariants(n[0], t));

out.tiles = ([[36.75, 3.06, 5], [36.75, 3.06, 20], [24.55, 9.48, 1], [-33.9, 151.2, 50], [0, 0, 3]] as Array<[number, number, number]>)
  .map(([lat, lng, r]) => [
    tileIdFor(lat, lng), coveringTiles(lat, lng, r),
    tileBounds(tileIdFor(lat, lng)).map((v) => roundTo(v, 9)),
  ]);

out.haversine = ([[36.75, 3.06, 36.76, 3.07], [0, 0, 0, 1], [36.7457, 3.06973, 36.7462, 3.0694],
  [-33.9, 151.2, 51.5, -0.12], [24.55, 9.48, 35.48, 6.46]] as Array<[number, number, number, number]>)
  .map(([a, b, c, d]) => roundTo(haversineKm(a, b, c, d), 9));

// Sort keys so the two JSON documents compare byte-for-byte.
const sorted = Object.fromEntries(Object.keys(out).sort().map((k) => [k, out[k]]));
process.stdout.write(JSON.stringify(sorted));
