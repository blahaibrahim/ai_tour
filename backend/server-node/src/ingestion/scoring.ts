/**
 * Interest scoring — deterministic answer to "would a traveller be glad
 * they went?", computed at ingestion time so route generation
 * (routes/itinerary.ts) can filter and rank without re-deriving this per
 * request. Weights match the table in docs/backend/12.
 *
 * Deliberately not an LLM call: this needs to be cheap (runs once per POI per
 * tile, not per user request), explainable (`score_breakdown` is stored
 * alongside the total specifically so a bad ranking can be debugged), and
 * stable (the same inputs always produce the same score, which an LLM
 * judgement would not guarantee).
 */
import { roundTo } from "../text";
import { OsmTags, WikidataItem } from "../types";

/**
 * Names that slipped past Overpass's tag filter (docs/backend/12's query
 * already excludes tourism=hotel/information/etc., but a generic-sounding
 * *name* on an otherwise-tagged POI — "Souvenir Shop" tagged tourism=gift
 * would already be excluded, but a mistagged tourism=attraction named
 * "Parking" happens in practice) gets caught here instead.
 *
 * `\b` is ASCII-only in JavaScript, which is exactly right here: every
 * alternative in the pattern is an ASCII word.
 */
const GENERIC_NAME_RE =
  /\b(parking|toilets?|wc|restrooms?|souvenir|gift ?shop|snack ?bar|car ?park|bus ?stop|entrance|exit|reception|ticket office)\b/i;

/**
 * Places whose *name* says they are closed to visitors even when their tags
 * don't. "Djenane El Mithak (Résidence d'Etat)" carries no `barrier` and no
 * `office=diplomatic`, so nothing else catches it — it reached the offered
 * candidate list as an ordinary park. Embassies are normally excluded by tag
 * in ingestion/overpass.ts; the name is the backstop for the ones tagged
 * incompletely.
 */
const CLOSED_TO_VISITORS_RE =
  /(r[ée]sidence\s+d\s*['’]?\s*[ée]tat|ambassade|embassy|consulat(e)?|chancellerie)/iu;

const RICHNESS_TAGS = ["website", "opening_hours", "description", "image"] as const;

/**
 * A walled/fenced enclosure mapped as a park with nothing saying it is
 * public — `barrier=wall` + `leisure=park` and no knowledge-base link,
 * tourism tag, historic tag or `access`.
 *
 * In Algiers this pattern is state residences and private villa grounds:
 * "Résidence d'Etat", "Domaine Bensmen", "Villa Montfeld", "Villa Sidi
 * Allaoui", and a plant nursery — all of which a naive `leisure=park` rule
 * reads as public parks worth 25 points, ahead of actual mosques.
 *
 * A **penalty and not an exclusion**, because the signal is ambiguous rather
 * than wrong: Dar Aziza, a 16th-century Ottoman palace, carries exactly the
 * same tags as Villa Montfeld and nothing in OSM distinguishes them. Scoring
 * it down puts it below every properly-tagged landmark while leaving it
 * available in a sparse area, which dropping it would not.
 */
function isWalledEnclosure(osmTags: OsmTags): boolean {
  const barrier = osmTags.barrier;
  if (barrier !== "wall" && barrier !== "fence") return false;
  if (osmTags.leisure !== "park") return false;
  const access = osmTags.access;
  return !(
    osmTags.wikidata ||
    osmTags.wikipedia ||
    osmTags.tourism ||
    osmTags.historic ||
    access === "yes" ||
    access === "public" ||
    access === "permissive"
  );
}

export interface ScoreInput {
  category: string;
  name: string;
  osmTags: OsmTags;
  wikidataMatch: WikidataItem | null;
  wikipediaFound: boolean;
  pageviews30d: number | null;
  hasPhoto: boolean;
}

export type ScoreBreakdown = Record<string, number>;

/**
 * Returns [score, breakdown]. `breakdown` is stored verbatim in
 * `locations.score_breakdown` — see docs/backend/12's "why this needs a
 * breakdown column" note.
 */
export function computeScore(input: ScoreInput): [number, ScoreBreakdown] {
  const { category, name, osmTags, wikidataMatch, wikipediaFound, pageviews30d, hasPhoto } = input;
  const breakdown: ScoreBreakdown = {};

  if (GENERIC_NAME_RE.test(name)) {
    breakdown.generic_name_penalty = -30;
    return [-30, breakdown];
  }

  if (CLOSED_TO_VISITORS_RE.test(name)) {
    breakdown.closed_to_visitors = -30;
    return [-30, breakdown];
  }

  if (isWalledEnclosure(osmTags)) {
    breakdown.walled_private_grounds = -20;
  }

  if (wikidataMatch) {
    if (wikidataMatch.is_unesco) {
      breakdown.unesco_world_heritage = 40;
    } else if (wikidataMatch.has_heritage) {
      breakdown.heritage_designation = 25;
    }

    if ((wikidataMatch.sitelinks ?? 0) >= 3) {
      breakdown.multilingual_coverage = 15;
    }
  }

  if (wikipediaFound) {
    breakdown.wikipedia_article = 20;
  }

  if (pageviews30d && pageviews30d > 0) {
    // log10(30) ≈ 1.5 -> ~6 pts (barely-known); log10(3000) ≈ 3.5 -> ~15
    // pts (regionally known); log10(300000) ≈ 5.5 -> 25 pts, capped
    // (genuinely famous). Log-scaled because raw pageviews span several
    // orders of magnitude between "local landmark" and "UNESCO site
    // everyone's heard of" — a linear scale would make everything below
    // the famous tier score near zero.
    const pvScore = Math.min(25.0, Math.log10(pageviews30d) * 6.25);
    breakdown.pageviews = roundTo(pvScore, 1);
  }

  if (hasPhoto) {
    breakdown.has_photo = 10;
  }

  if (osmTags.wikidata || osmTags.wikipedia) {
    breakdown.osm_linked_to_wikidata = 8;
  }

  const richness = RICHNESS_TAGS.reduce((sum, tag) => sum + (osmTags[tag] ? 2 : 0), 0);
  if (richness) {
    breakdown.osm_tag_richness = Math.min(richness, 8);
  }

  const normalizedCategory = category.trim().toLowerCase();
  if (normalizedCategory !== "attraction" && normalizedCategory !== "point of interest") {
    breakdown.specific_category = 10;
  }

  if ("natural" in osmTags || "historic" in osmTags || osmTags.leisure === "park") {
    breakdown.natural_or_historic_baseline = 15;
  }

  const sourceCount = 1 + (wikidataMatch ? 1 : 0) + (wikipediaFound ? 1 : 0);
  if (sourceCount >= 2) {
    breakdown.corroborated = 10;
  }

  const total = Object.values(breakdown).reduce((sum, value) => sum + value, 0);
  return [total, breakdown];
}
