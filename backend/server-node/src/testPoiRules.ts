/**
 * Regression checks for POI categorization, exclusion, scoring and dedupe.
 *
 *     npm test
 *
 * A direct port of `backend/server/test_poi_rules.py`, kept in the same
 * zero-dependency style it was deliberately written in (no pytest there, no
 * vitest here). No network — every case below is a real tag set taken from
 * live Overpass output for Algiers, kept as a fixture so the rules that
 * produced today's candidate list can't silently regress.
 *
 * The port adds a short section for the Unicode helpers in `text.ts`, because
 * Python's string methods are Unicode-aware by default and JavaScript's are
 * not — that is the one class of difference capable of degrading photo
 * matching and dedupe without raising anything.
 *
 * Each case names the failure it exists to prevent.
 */
import {
  categoryFromTags,
  deduplicate,
  distanceM,
  DUPLICATE_RADIUS_M,
  isRealName,
  nameVariants,
} from "./ingestion/overpass";
import { computeScore } from "./ingestion/scoring";
import { capitalize, normalizeFold, titleCase } from "./text";
import { OsmTags, Poi } from "./types";

const failures: string[] = [];

function check(label: string, got: unknown, expected: unknown): void {
  const a = JSON.stringify(got);
  const b = JSON.stringify(expected);
  if (a !== b) {
    failures.push(`${label}\n      expected ${b}\n      got      ${a}`);
  }
}

function poi(
  osmId: number,
  name: string,
  tags: OsmTags,
  lat: number,
  lng: number,
  osmType = "way",
): Poi {
  return {
    osm_type: osmType,
    osm_id: osmId,
    name,
    category: categoryFromTags(tags) ?? "Attraction",
    lat,
    lng,
    bounds: null,
    tags,
    wikidata_qid: tags.wikidata ?? null,
    wikipedia: tags.wikipedia ?? null,
  };
}

// --- categorization --------------------------------------------------------
// `historic=yes` shipped two Algiers mosques to the app labelled "Yes".
check(
  "historic=yes place_of_worship -> Mosque, never 'Yes'",
  categoryFromTags({ historic: "yes", amenity: "place_of_worship", religion: "muslim" }),
  "Mosque",
);
check(
  "historic=heritage on a mosque prefers the mosque",
  categoryFromTags({
    historic: "heritage",
    amenity: "place_of_worship",
    religion: "muslim",
    building: "mosque",
  }),
  "Mosque",
);
check(
  "a specific historic value still wins",
  categoryFromTags({ historic: "castle", castle_type: "palace" }),
  "Castle",
);
check(
  "historic=yes with nothing else is not a category called 'Yes'",
  categoryFromTags({ historic: "yes" }),
  "Historic site",
);

// --- exclusions ------------------------------------------------------------
// Embassies are tagged leisure=park and took four of the top ten candidates.
check(
  "embassy compound is not a park",
  categoryFromTags({
    office: "diplomatic",
    diplomatic: "embassy",
    embassy: "yes",
    leisure: "park",
    barrier: "wall",
  }),
  null,
);
check(
  "a historic fort on military land is still visitable",
  categoryFromTags({ historic: "fort", military: "bunker" }),
  "Fort",
);
check(
  "an active military site with no heritage value is not",
  categoryFromTags({ military: "barracks", tourism: "attraction" }),
  null,
);
check(
  "Serkadji Prison (barrier=wall) is a museum, not a compound",
  categoryFromTags({ barrier: "wall", tourism: "museum", wikidata: "Q3403985" }),
  "Museum",
);

// --- names -----------------------------------------------------------------
// Heritage-register ids get tagged as names: 214145, 937605, 116pa466551.
check("register id is not a name", isRealName("214145"), false);
check("mostly-digit id is not a name", isRealName("116pa466551"), false);
check("two-letter name is not a name", isRealName("Ne"), false);
check("a real name with a number survives", isRealName("ilot 661"), true);
check("an Arabic name survives", isRealName("مقام الشهيد"), true);

// --- scoring ---------------------------------------------------------------
function score(name: string, tags: OsmTags): number {
  return computeScore({
    category: categoryFromTags(tags) ?? "Attraction",
    name,
    osmTags: tags,
    wikidataMatch: null,
    wikipediaFound: false,
    pageviews30d: null,
    hasPhoto: false,
  })[0];
}

const walled: OsmTags = { barrier: "wall", leisure: "park" };
check(
  "walled private grounds are penalized below a real park",
  score("Villa Montfeld", walled) < score("Hamma Park", { leisure: "park", access: "yes" }),
  true,
);
check("...but survive as a candidate rather than being deleted", score("Dar Aziza", walled) >= 0, true);
check(
  "a state residence is rejected outright",
  score("Djenane El Mithak (Résidence d'Etat)", { leisure: "park" }) < 0,
  true,
);
check(
  "an embassy named but untagged is rejected too",
  score("Ambassade du Brésil", { leisure: "park" }) < 0,
  true,
);
check(
  "a walled park with a wikidata link is not penalized",
  score("Jardin d'Essai", { ...walled, wikidata: "Q123" }) > 0,
  true,
);

// --- deduplication ---------------------------------------------------------
// The reported bug: one monument, three cards, in French/English/Arabic.
const martyrs = [
  poi(
    370342095,
    "Martyrs Memorial",
    {
      historic: "memorial",
      name: "Martyrs Memorial",
      "name:fr": "Mémorial du martyr",
      "name:ar": "مقام الشهيد",
      wikidata: "Q3056085",
    },
    36.7457,
    3.06973,
  ),
  poi(
    2700208215,
    "Martyrs Memorial",
    { tourism: "viewpoint", name: "مقام الشهيد", "name:en": "Martyrs Memorial" },
    36.7462,
    3.0694,
    "node",
  ),
  poi(
    7023985185,
    "MaQam echahid",
    { historic: "monument", name: "MaQam echahid", "name:ar": "مقام الشهيد" },
    36.74571,
    3.06974,
    "node",
  ),
  poi(
    2545150691,
    "Martyrs Memorial 2",
    { tourism: "viewpoint", name: "Martyrs Memorial 2" },
    36.74646,
    3.06926,
    "node",
  ),
];
const deduped = deduplicate([...martyrs]);
check("one monument in three languages collapses to one card", deduped.length, 1);
check("the survivor is the wikidata-linked record", deduped[0].osm_id, 370342095);
check(
  "the survivor inherits the duplicates' name variants",
  nameVariants(deduped[0].tags).has("martyrs memorial 2"),
  true,
);

// Same subject, same id, but genuinely two places 1.8 km apart.
const benAknoun = [
  poi(
    248872093,
    "Ben Aknoun Amusement Park",
    { tourism: "theme_park", name: "Ben Aknoun Amusement Park", wikidata: "Q2896344" },
    36.763,
    3.021,
  ),
  poi(
    248872080,
    "Ben Aknoun Zoo",
    { tourism: "zoo", name: "Ben Aknoun Zoo", wikidata: "Q2896344" },
    36.779,
    3.029,
  ),
];
check("a shared wikidata id across 1.8 km does NOT merge", deduplicate([...benAknoun]).length, 2);

// Same name, different cities — must stay separate.
const squares = [
  poi(31242440, "Place des Martyrs", { leisure: "park", name: "Place des Martyrs" }, 36.66782, 3.09464),
  poi(475312883, "Place des Martyrs", { leisure: "park", name: "Place des Martyrs" }, 36.605, 3.08849),
];
check("same name 7 km apart does NOT merge", deduplicate([...squares]).length, 2);

// Accents and case: "ilot 661" vs "ÎLOT 661", 7 m apart.
const ilot = [
  poi(6127222785, "ilot 661", { tourism: "artwork", name: "ilot 661" }, 36.77, 3.06, "node"),
  poi(6062724102, "ÎLOT 661", { tourism: "artwork", name: "ÎLOT 661" }, 36.77005, 3.06005, "node"),
];
check("accent/case variants of one name merge", deduplicate([...ilot]).length, 1);

// A café next to a mosque is not the mosque.
const neighbours = [
  poi(
    1,
    "Ketchaoua Mosque",
    {
      historic: "heritage",
      amenity: "place_of_worship",
      religion: "muslim",
      name: "Ketchaoua Mosque",
    },
    36.7839,
    3.0606,
  ),
  poi(2, "Café Malakoff", { tourism: "attraction", name: "Café Malakoff" }, 36.78392, 3.06062),
];
check("adjacent but differently-named places do NOT merge", deduplicate([...neighbours]).length, 2);

// The enclosure / route-diversity checks that used to sit here belonged to the
// old `routes/itinerary.ts` (`_encloses` / `_drop_enclosed`). That module has
// been removed — see `src/routeGeneration/` for the replacement, whose own
// clustering and ordering rules get their tests once the domain layer is
// implemented. Everything above is the POI ingestion pipeline, which the new
// design still depends on as its `api_seeded` source.

check(
  "distance helper agrees with the dedupe radius",
  Math.round(distanceM({ lat: 36.7457, lng: 3.06973 }, { lat: 36.7462, lng: 3.0694 })) <
    DUPLICATE_RADIUS_M,
  true,
);

// --- Unicode string helpers ------------------------------------------------
// New in the TypeScript port. Python's str methods are Unicode-aware and
// JavaScript's are not, so these pin the three behaviours the ported matching
// rules depend on. Getting any of them wrong degrades photo matching quietly
// rather than raising.
check("accents fold away for comparison", normalizeFold("ÎLOT 661"), "ilot 661");
check("Arabic alef variants normalize", normalizeFold("أحمد"), "احمد");
check("teh marbuta folds to heh", normalizeFold("قلعة"), "قلعه");
check("punctuation becomes space, not deletion", normalizeFold("Sidi M'Cid"), "sidi m cid");
check("Arabic survives the alnum filter", normalizeFold("مقام الشهيد"), "مقام الشهيد");
check("capitalize lowercases the tail, as Python does", capitalize("cave entrance"), "Cave entrance");
check("capitalize on an all-caps value", capitalize("RUINS"), "Ruins");
check("title-case treats digits as boundaries", titleCase("a1b"), "A1B");
check("title-case a denomination", titleCase("sunni"), "Sunni");

if (failures.length > 0) {
  console.log(`FAILED (${failures.length}):`);
  for (const f of failures) console.log(`  - ${f}`);
  process.exit(1);
}
console.log("all POI rule checks passed");
