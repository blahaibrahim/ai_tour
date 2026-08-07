/**
 * LLM-powered blurb rewrite and translation for ingested POIs (docs/backend/08, 12).
 *
 * Wikipedia extracts are encyclopedic in tone and often too long for app cards.
 * This module rewrites them into concise, editorial-style blurbs and optionally
 * translates them into the project's supported locales (fr, ar).
 *
 * Every function degrades silently on LLM failure — the caller should treat
 * a missing return value as "use the raw blurb" rather than erroring out.
 *
 * Cost note: called per-POI at ingestion time, not per-request. The tile cache
 * (poi_tiles) ensures each POI is only processed once per cache TTL (60 days),
 * so the LLM cost is amortised. A cold tile of 20 POIs = 20 rewrite calls.
 * At Gemini Flash's free tier limits this is negligible, but watch if you
 * start ingesting thousands of tiles back-to-back.
 */
import { chat } from "../llm";
import { getLogger } from "../logger";
import { Facts } from "../types";

const logger = getLogger("ingestion.rewrite");

const MAX_INPUT_CHARS = 1200; // clip Wikipedia extract before sending to LLM

/**
 * Rewrite a Wikipedia extract into a concise, editorial blurb (≤200 chars).
 *
 * Returns null if the LLM fails so the caller can fall back to truncation.
 */
export async function rewriteBlurb(
  rawText: string,
  locationName: string,
  category: string,
): Promise<string | null> {
  if (!rawText || !rawText.trim()) {
    return null;
  }

  const clipped = rawText.slice(0, MAX_INPUT_CHARS);

  try {
    const result = (
      await chat(
        [
          {
            role: "system",
            content:
              "You are writing concise captions for a travel app. " +
              "Rewrite the following Wikipedia text as a single, vivid, " +
              "editorial sentence (max 200 characters). " +
              "Keep proper nouns and dates. Omit administrative detail. " +
              "Write directly — no 'It is…' or 'This is…' opener. " +
              "Reply with ONLY the rewritten sentence, nothing else.",
          },
          {
            role: "user",
            content: `Location: ${locationName} (${category})\nWikipedia extract:\n${clipped}`,
          },
        ],
        { jsonMode: false, maxTokens: 200, temperature: 0.4 },
      )
    ).trim();

    // Sanity: must be a non-trivial length (at least 25 chars) and not too long
    if (result && result.length >= 25 && result.length <= 300) {
      return result.slice(0, 250); // cap just in case
    }
    return null;
  } catch (error) {
    logger.warning(
      `Blurb rewrite failed for ${locationName}: ${error instanceof Error ? error.message : error}`,
    );
    return null;
  }
}

/**
 * Write a blurb for a POI that has no Wikipedia article, from the OSM
 * facts `describe.collectFacts` gathered.
 *
 * Distinct from `rewriteBlurb`, which condenses text that already exists.
 * Here there is no source text — only a handful of tags — so the prompt is
 * explicit that the model may not add anything it wasn't given. Without that
 * constraint this is an invitation to invent a founding date and an architect
 * for a municipal car park.
 *
 * Returns null on any failure or if the result looks unusable, so the caller
 * falls back to the deterministic sentence.
 */
export async function describeFromFacts(facts: Facts): Promise<string | null> {
  const name = facts.name || "this place";
  const lines = [`Name: ${name}`];
  if (facts.kind) lines.push(`Type: ${facts.kind}`);
  if (facts.embassy) lines.push(`Role: ${facts.embassy}`);
  if (facts.qualifiers && facts.qualifiers.length > 0) {
    lines.push(`Attributes: ${facts.qualifiers.join("; ")}`);
  }
  if (facts.place) lines.push(`City: ${facts.place}`);
  if (facts.street) lines.push(`Street: ${facts.street}`);

  // With only a name and nothing else there is nothing for the model to work
  // from, and asking anyway is how you get invented history.
  if (lines.length < 2) {
    return null;
  }

  let result: string;
  try {
    result = (
      (await chat(
        [
          {
            role: "system",
            content:
              "You write one-sentence captions for a travel app. " +
              "You will be given verified facts about a place. " +
              "Write ONE inviting sentence (max 180 characters) using " +
              "ONLY those facts. Do not invent history, dates, " +
              "architects, significance, or details you were not given. " +
              "Do not repeat the place's name — the app shows it above " +
              "the caption. Do not start with 'It is' or 'This is'. " +
              "Reply with ONLY the sentence.",
          },
          { role: "user", content: lines.join("\n") },
        ],
        { jsonMode: false, maxTokens: 120, temperature: 0.5 },
      )) || ""
    ).trim();
  } catch (error) {
    logger.warning(
      `Fact-based description failed for ${name}: ${error instanceof Error ? error.message : error}`,
    );
    return null;
  }

  result = result.trim().replace(/^"+|"+$/g, "");
  if (!(result.length >= 20 && result.length <= 260)) {
    return null;
  }
  // A model that starts explaining itself has not written a caption.
  const lowered = result.toLowerCase();
  if (["i ", "as an", "sorry", "i'm sorry", "unfortunately"].some((p) => lowered.startsWith(p))) {
    return null;
  }
  return result;
}

/**
 * Translate a blurb into French (fr) and Arabic (ar).
 *
 * Returns an object with keys 'fr' and 'ar'. Missing translations are
 * omitted rather than returned as null — call sites should check key presence.
 *
 * Proper nouns (place names in French/Arabic contexts) are a known failure
 * mode for machine translation; Arabic especially benefits from human review
 * before publication. These are stored as a starting point, not as final copy.
 */
export async function translateBlurbs(
  enBlurb: string,
  locationName: string,
): Promise<Record<string, string>> {
  const results: Record<string, string> = {};
  if (!enBlurb || !enBlurb.trim()) {
    return results;
  }

  const targetLangs: Record<string, string> = { fr: "French", ar: "Modern Standard Arabic" };
  for (const [code, langName] of Object.entries(targetLangs)) {
    try {
      const result = (
        await chat(
          [
            {
              role: "system",
              content:
                `Translate the following travel app caption into ${langName}. ` +
                "Keep proper nouns, place names, and dates as-is. " +
                "Reply with ONLY the translated text, nothing else.",
            },
            { role: "user", content: `Location: ${locationName}\n${enBlurb}` },
          ],
          { jsonMode: false, maxTokens: 200, temperature: 0.3 },
        )
      ).trim();
      if (result && result.length > 15) {
        results[code] = result.slice(0, 300);
      }
    } catch (error) {
      logger.warning(
        `Translation to ${code} failed for ${locationName}: ` +
          `${error instanceof Error ? error.message : error}`,
      );
    }
  }

  return results;
}
