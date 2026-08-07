/**
 * One-off: translate the curated locations' English blurbs into fr and ar.
 *
 * Skips any (location, locale) pair that already exists, so it is safe to
 * re-run. The Python version declared its output shape with a pydantic model
 * passed as `response_schema`; the JS SDK takes the same thing as a plain
 * JSON-schema object, and the result is parsed the same way either way.
 *
 *     npm run translate:curated
 */
import { GoogleGenAI } from "@google/genai";

import { Config, requireGeminiKey } from "../config";
import { getAdminClient } from "../ingestion/supabaseAdmin";
import { unwrapRows } from "../supabase";

const TRANSLATION_SCHEMA = {
  type: "object",
  properties: {
    name: { type: "string" },
    blurb: { type: "string" },
  },
  required: ["name"],
};

interface TranslationOutput {
  name?: string;
  blurb?: string;
}

interface TranslationRow {
  location_id: string;
  name: string;
  blurb: string;
}

async function translateText(
  ai: GoogleGenAI,
  loc: TranslationRow,
  targetLang: string,
): Promise<TranslationOutput> {
  const prompt = `
    Translate the following location information to ${targetLang}.
    It is a curated location in Algeria.
    If the name is a proper noun (e.g. 'Maqam Echahid'), keep it appropriate for the language, or translate if standard.

    Name: ${loc.name}
    Blurb: ${loc.blurb ?? ""}

    Return a JSON object with 'name' and 'blurb'.
  `;

  const response = await ai.models.generateContent({
    model: "gemini-2.5-flash",
    contents: prompt,
    config: {
      maxOutputTokens: 2048,
      temperature: 0.1,
      responseMimeType: "application/json",
      responseSchema: TRANSLATION_SCHEMA,
    } as never,
  });

  return JSON.parse(response.text ?? "{}") as TranslationOutput;
}

async function main(): Promise<void> {
  if (!Config.SUPABASE_URL) {
    throw new Error("SUPABASE_URL is not set. Add it to backend/.env.");
  }
  const supabase = getAdminClient();
  const ai = new GoogleGenAI({ apiKey: requireGeminiKey() });

  console.log("Fetching curated locations (English translations)...");
  const locations = await unwrapRows<TranslationRow>(
    supabase.from("location_translations").select("location_id, name, blurb").eq("locale", "en"),
  );

  for (const loc of locations) {
    console.log(`Translating: ${loc.name}`);
    for (const lang of ["fr", "ar"]) {
      const existing = await unwrapRows<{ location_id: string }>(
        supabase
          .from("location_translations")
          .select("location_id")
          .eq("location_id", loc.location_id)
          .eq("locale", lang),
      );
      if (existing.length > 0) {
        console.log(`  [${lang}] already exists, skipping.`);
        continue;
      }

      console.log(`  [${lang}] Translating...`);
      try {
        const translated = await translateText(
          ai,
          loc,
          lang === "fr" ? "French" : "Arabic (Modern Standard)",
        );
        const { error } = await supabase.from("location_translations").insert({
          location_id: loc.location_id,
          locale: lang,
          name: translated.name || loc.name,
          blurb: translated.blurb,
        });
        if (error) throw error;
        console.log(`  [${lang}] Saved.`);
      } catch (error) {
        console.log(`  [${lang}] Error: ${error instanceof Error ? error.message : error}`);
      }
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
