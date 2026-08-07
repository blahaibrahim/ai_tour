/**
 * Human-readable descriptions for POIs that Wikipedia has never heard of.
 *
 * ## Why this exists
 *
 * The blurb pipeline had exactly one good path — rewrite a Wikipedia extract —
 * and a throwaway `else` branch for everything else. Since only ~10 of 203
 * catalogue rows carry a `wikipedia_title`, that `else` branch produced almost
 * every blurb in the app, and it produced them by pasting raw OSM tag values
 * into a format string. The live catalogue is the evidence:
 *
 *     "A attraction attraction."   x28     (tourism=attraction)
 *     "A park."                    x31     (nothing but the category)
 *     "A historic yes."            x3      (historic=yes, a tag meaning
 *                                           "this is historic", not a noun)
 *     "A artwork in the area."     x4      (no article agreement)
 *
 * So: 190 of 203 blurbs were some flavour of broken. This module replaces that
 * branch with something that reads like English, and — when an LLM is reachable
 * — hands the same structured facts to it for a sentence with some life in it.
 *
 * ## Rules
 *
 * Nothing here invents facts. Every clause traces to a tag that is actually
 * set, which is what keeps the deterministic path safe to ship unattended and
 * gives the LLM path a factual frame it is told not to depart from.
 */
import { getLogger } from "../logger";
import { capitalize, titleCase } from "../text";
import { Facts, HeritageStatus, OsmTags } from "../types";
import { describeFromFacts } from "./rewrite";

const logger = getLogger("ingestion.describe");

// OSM uses "yes" to mean "this key applies" — it is a flag, not a noun, and
// pasting it into prose is where "A historic yes." came from.
const NON_NOUNS = new Set(["yes", "y", "true", "1", ""]);

const VOWELS = "aeiou";

// Tag values whose OSM spelling is not what a person would call the thing.
const PRETTY: Record<string, string> = {
  place_of_worship: "place of worship",
  attraction: "visitor attraction",
  artwork: "public artwork",
  viewpoint: "viewpoint",
  theme_park: "theme park",
  nature_reserve: "nature reserve",
  city_gate: "city gate",
  // historic=heritage marks a protected site; on its own "heritage" is not a
  // noun for a thing, which is where "A heritage in Algiers." came from.
  heritage: "heritage site",
  archaeological_site: "archaeological site",
  water_tap: "public fountain",
  powder_magazine: "powder magazine",
  battlefield: "battlefield",
  wood: "woodland",
  water: "body of water",
  bay: "bay",
  ruins: "ruins",
  manor: "manor house",
  memorial: "memorial",
  monument: "monument",
  castle: "castle",
  museum: "museum",
  zoo: "zoo",
  beach: "beach",
  park: "park",
  garden: "garden",
  tomb: "tomb",
  bridge: "bridge",
  church: "church",
  mosque: "mosque",
  hotel: "hotel",
};

// ISO 3166-1 alpha-2 for the embassies that actually appear in this catalogue;
// anything else falls back to the raw code rather than guessing.
const COUNTRIES: Record<string, string> = {
  FR: "France",
  NL: "the Netherlands",
  BR: "Brazil",
  ES: "Spain",
  IT: "Italy",
  DE: "Germany",
  GB: "the United Kingdom",
  US: "the United States",
  RU: "Russia",
  CN: "China",
  TR: "Türkiye",
  PT: "Portugal",
  BE: "Belgium",
  TN: "Tunisia",
  MA: "Morocco",
  EG: "Egypt",
  SA: "Saudi Arabia",
  QA: "Qatar",
  AE: "the UAE",
};

function isNoun(value: unknown): value is string {
  return typeof value === "string" && !NON_NOUNS.has(value.trim().toLowerCase());
}

function pretty(value: string): string {
  const key = value.trim().toLowerCase();
  return PRETTY[key] ?? key.replace(/_/g, " ").trim();
}

/** Upper-cases the first character only, leaving proper nouns intact. */
function sentenceCase(text: string): string {
  if (!text) return text;
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/**
 * "a" / "an" by sound of the first letter. Cheap, but it is the whole
 * reason the old output read as "A artwork" / "A attraction".
 */
function article(phrase: string): string {
  return VOWELS.includes(phrase.slice(0, 1).toLowerCase()) ? "an" : "a";
}

/**
 * The noun this place *is*, chosen from the most specific tag that carries
 * one. Order matters: `historic=castle` says more than `building=yes`, and the
 * bare category is the last resort.
 */
function kindOf(category: string | null | undefined, tags: OsmTags): string | null {
  const t = tags ?? {};

  if (isNoun(t.historic)) {
    const kind = pretty(t.historic);
    const castleType = t.castle_type;
    if (kind === "castle" && isNoun(castleType)) {
      const sub = pretty(castleType);
      // castle_type=palace/fortress/citadel name the building outright —
      // "a palace castle" is not a thing. Others qualify it ("a hill
      // castle"), so those keep the head noun.
      if (["palace", "fortress", "citadel", "manor house", "stately"].includes(sub)) {
        return sub === "stately" ? "palace" : sub;
      }
      return `${sub} castle`;
    }
    return kind;
  }

  if (isNoun(t.memorial)) {
    return pretty(t.memorial);
  }

  for (const key of ["leisure", "natural", "tourism", "man_made", "amenity", "shop"] as const) {
    const value = t[key];
    if (isNoun(value)) return pretty(value);
  }

  if (isNoun(t.building)) {
    return pretty(t.building);
  }

  if (category && isNoun(category)) {
    return pretty(category);
  }
  return null;
}

/** Short factual clauses, each traceable to a set tag. */
function qualifiersOf(tags: OsmTags, heritageStatus: HeritageStatus): string[] {
  const t = tags ?? {};
  const out: string[] = [];

  if (heritageStatus === "unesco_world_heritage") {
    out.push("part of a UNESCO World Heritage site");
  } else if (heritageStatus === "heritage_listed") {
    out.push("heritage-listed");
  }

  const religion = t.religion;
  const denomination = t.denomination;
  if (isNoun(religion) && t.amenity === "place_of_worship") {
    const label = isNoun(denomination) ? pretty(denomination) : pretty(religion);
    // Denominations are proper nouns — "sunni" reads as a typo.
    out.push(titleCase(label));
  }

  if (isNoun(t.start_date)) {
    out.push(`dating from ${t.start_date}`);
  }

  const operator = t.operator;
  if (isNoun(operator) && String(operator).length < 40) {
    out.push(`run by ${operator}`);
  }

  const access = t.access;
  if (typeof access === "string" && ["private", "no"].includes(access.toLowerCase())) {
    out.push("not open to the public");
  }

  return out;
}

/**
 * Embassies are a big slice of this catalogue and read terribly through
 * the generic path ("A park." — they are tagged as their grounds).
 */
function embassyPhrase(tags: OsmTags): string | null {
  const t = tags ?? {};
  if (t.office !== "diplomatic" && !isNoun(t.embassy)) {
    return null;
  }
  const code = t.country;
  if (typeof code === "string" && code.trim()) {
    const raw = code.trim();
    const country = COUNTRIES[raw.toUpperCase()] ?? titleCase(raw);
    return `the diplomatic mission of ${country}`;
  }
  return "a diplomatic mission";
}

/** The pure clause builders, exposed for the parity harness. See photos.ts. */
export const internals = {
  kindOf: (category: string | null | undefined, tags: OsmTags) => kindOf(category, tags),
  qualifiersOf: (tags: OsmTags, heritageStatus: HeritageStatus) =>
    qualifiersOf(tags, heritageStatus),
  embassyPhrase: (tags: OsmTags) => embassyPhrase(tags),
  article: (phrase: string) => article(phrase),
  pretty: (value: string) => pretty(value),
};

export interface CollectFactsInput {
  name: string;
  category: string | null | undefined;
  tags: OsmTags;
  heritageStatus?: HeritageStatus;
  place?: string | null;
}

/** The structured frame both description paths work from. */
export function collectFacts(input: CollectFactsInput): Facts {
  const { name, category, heritageStatus = null, place = null } = input;
  const tags = input.tags ?? {};
  return {
    name,
    kind: kindOf(category, tags),
    embassy: embassyPhrase(tags),
    qualifiers: qualifiersOf(tags, heritageStatus),
    place: place || tags["addr:city"] || null,
    street: tags["addr:street"] ?? null,
    // An explicit description tag beats anything either path can compose.
    description: tags["description:en"] || tags.description || null,
    website: tags.website ?? null,
  };
}

/**
 * Deterministic description. Always returns a readable sentence.
 *
 * This is the floor, not the ceiling — it runs when no LLM is reachable,
 * and as the fallback when the LLM declines or misbehaves.
 */
export function compose(facts: Facts): string {
  const explicit = facts.description;
  if (typeof explicit === "string" && explicit.trim().length >= 20) {
    const text = explicit.trim();
    return /[.!?]$/.test(text) ? text : `${text}.`;
  }

  const place = facts.place;
  const inPlace = place ? ` in ${place}` : "";

  if (facts.embassy) {
    // Not Python's str.capitalize(): it lowercases everything after the first
    // character, which turned "…mission of France" into "…of france".
    return `${sentenceCase(`${facts.embassy}${inPlace}`)}.`;
  }

  const kind = facts.kind;
  const qualifiers = [...(facts.qualifiers ?? [])];

  if (!kind) {
    // Nothing factual to say beyond where it is. Better an honest, plain
    // line than a confidently wrong one.
    return place ? `A point of interest${inPlace}.` : "A point of interest.";
  }

  // Fold a leading adjectival qualifier into the noun phrase so it reads as
  // "A heritage-listed mosque" rather than "A mosque, heritage-listed".
  let lead = "";
  for (const candidate of [...qualifiers]) {
    if (candidate === "heritage-listed" || !candidate.includes(" ")) {
      lead = `${candidate} `;
      qualifiers.splice(qualifiers.indexOf(candidate), 1);
      break;
    }
  }

  const phrase = `${lead}${kind}`;
  let sentence = `${capitalize(article(phrase))} ${phrase}${inPlace}`;

  if (qualifiers.length > 0) {
    sentence += `, ${qualifiers.slice(0, 2).join(", ")}`;
  }
  return `${sentence}.`;
}

/**
 * Whether there is enough substance for a written sentence to beat the
 * deterministic one.
 *
 * Measured, not assumed: asked to describe a POI whose only facts are
 * "type: park, city: Algiers", the model returns "Explore this park located
 * in Algiers." — strictly worse than "A park in Algiers.", because it pads
 * the same information with filler. Told not to invent (as it must be), it
 * has nothing else to work with. So the call is only made when the facts
 * can actually carry a sentence.
 */
export function isWorthWriting(facts: Facts): boolean {
  if (facts.description) return true;
  if (facts.embassy) return false; // the deterministic phrasing is already exact
  const qualifiers = facts.qualifiers ?? [];
  if (qualifiers.length >= 2) return true;
  return Boolean(facts.kind) && qualifiers.length >= 1;
}

/**
 * LLM-written description when the facts justify it, deterministic otherwise.
 *
 * The LLM is given only the collected facts and told not to add any, which
 * is what keeps this from inventing history for a POI whose entire record is
 * three OSM tags. Any failure — unreachable, empty, wrong length, or an
 * answer that smells like a refusal — falls back to `compose`.
 */
export async function describe(facts: Facts, options: { useLlm?: boolean } = {}): Promise<string> {
  const { useLlm = true } = options;
  const baseline = compose(facts);
  if (!useLlm || !isWorthWriting(facts)) {
    return baseline;
  }

  let written: string | null = null;
  try {
    written = await describeFromFacts(facts);
  } catch (error) {
    logger.warning(
      `LLM description failed for ${JSON.stringify(facts.name)}: ` +
        `${error instanceof Error ? error.message : error}`,
    );
    return baseline;
  }

  return written || baseline;
}
