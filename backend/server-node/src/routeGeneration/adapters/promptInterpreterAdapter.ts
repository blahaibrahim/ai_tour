/**
 * Layer 4 — Prompt Interpreter Adapter.
 *
 * The single seam to the LLM used for turning free text into a theme plus
 * category preferences. Domain code (`domain/promptInterpreter.ts`) never
 * imports a provider SDK — it calls this file and gets back parsed,
 * untrusted JSON that it is responsible for validating against the real
 * vocabulary. That split matters here specifically: nothing this adapter
 * returns may be trusted as a real theme or category key on its own.
 *
 * Groq only, deliberately — unlike `llm.ts`'s `chat()`, this does not fall
 * back to Gemini. This call sits on the traveller's "Plan my route" path
 * (spec-adjacent latency budget, same reasoning as the routing provider), and
 * Groq's own measured latency for a small constrained-JSON completion is
 * ~1.6s against Gemini's ~5.5s at its fastest (see `llm.ts`'s docstring on
 * `prefer`). A route must still generate with no LLM at all — see
 * `domain/promptInterpreter.ts`'s fallback — so losing Groq only costs the
 * narrowing, never the route.
 */
import OpenAI from "openai";

import { Config, requireLlmKey } from "../../config";
import { extractJson, JsonExtractionError } from "../../jsonUtils";
import { getLogger } from "../../logger";
import { Locale } from "../types";

const logger = getLogger("routeGeneration.promptInterpreter");

export class PromptInterpreterUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PromptInterpreterUnavailableError";
  }
}

export interface VocabularyTheme {
  key: string;
  labelEn: string;
}

export interface VocabularyCategory {
  key: string;
  labelEn: string;
  poiCount: number;
}

export interface InterpretPromptInput {
  prompt: string;
  locale: Locale;
  themes: VocabularyTheme[];
  categories: VocabularyCategory[];
  /** Set on the retry pass: the keys the model returned that were not real,
   * so the second attempt is told what specifically to avoid repeating. */
  rejectedKeys?: string[];
}

/** What the model is asked to return. Untyped as far as callers outside this
 * file are concerned — `domain/promptInterpreter.ts` is the boundary that
 * turns this into something trusted. */
export interface RawInterpretation {
  theme: unknown;
  category_keys: unknown;
}

let client: OpenAI | null = null;

/** Its own client rather than `llm.ts`'s `getGroqClient()` — same
 * construction, but a shared singleton across two call sites is a coupling
 * neither side asked for, and this adapter must never reach for the Gemini
 * client that lives next to it in that file. */
function getClient(): OpenAI {
  if (client === null) {
    client = new OpenAI({ baseURL: Config.LLM_BASE_URL, apiKey: requireLlmKey() });
  }
  return client;
}

function buildPrompt(input: InterpretPromptInput): { system: string; user: string } {
  const themeList = input.themes.map((t) => `- ${t.key}: ${t.labelEn}`).join("\n");
  const categoryList = input.categories
    .map((c) => `- ${c.key}: ${c.labelEn} (${c.poiCount} places here)`)
    .join("\n");

  const system =
    "You read one sentence a traveller wrote describing the trip they want, and map it " +
    "onto a fixed vocabulary. You do not invent keys. You only ever return keys that " +
    "appear verbatim in the lists you are given.\n\n" +
    "Rules:\n" +
    '- "theme" is at most one key from the theme list, or null if nothing in the sentence ' +
    "points at a theme.\n" +
    '- "category_keys" is zero or more keys from the category list — the places the ' +
    "sentence calls out specifically. These narrow preference, not a hard filter: " +
    'a request for "beaches" should return the beach-like category keys, and the route ' +
    "will still be free to include other good stops alongside them.\n" +
    "- Respect negation: \"no museums\" must not return the museum key.\n" +
    "- A sentence with nothing recognisable in it returns theme: null and category_keys: [].\n" +
    "- Reply with ONLY a JSON object: {\"theme\": string|null, \"category_keys\": string[]}.";

  const rejected =
    input.rejectedKeys && input.rejectedKeys.length > 0
      ? `\n\nYour previous answer used these keys, which do not exist: ${input.rejectedKeys.join(", ")}. ` +
        "Use only keys from the lists below, verbatim."
      : "";

  const user =
    `Traveller's description (locale: ${input.locale}): "${input.prompt}"\n\n` +
    `Themes:\n${themeList || "(none available)"}\n\n` +
    `Categories:\n${categoryList || "(none available)"}` +
    rejected;

  return { system, user };
}

/**
 * One completion, parsed but not yet validated. Throws
 * `PromptInterpreterUnavailableError` on any provider or parse failure —
 * the domain layer decides what a failure means for the response, this file
 * only knows that it couldn't get an answer.
 */
export async function interpretPromptRaw(input: InterpretPromptInput): Promise<RawInterpretation> {
  const { system, user } = buildPrompt(input);
  const messages = [
    { role: "system" as const, content: system },
    { role: "user" as const, content: user },
  ];

  const baseParams: Record<string, unknown> = {
    messages,
    max_tokens: 200,
    temperature: 0.2,
    response_format: { type: "json_object" },
    reasoning_effort: "none",
  };

  const attempt = async (model: string): Promise<string> => {
    const response = await getClient().chat.completions.create(
      { ...baseParams, model } as unknown as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming,
    );
    const content = response.choices[0]?.message?.content;
    if (!content) throw new PromptInterpreterUnavailableError("Empty response from Groq");
    return content;
  };

  let content: string;
  try {
    content = await attempt(Config.LLM_MODEL);
  } catch (firstError) {
    logger.warning(
      `Groq primary model (${Config.LLM_MODEL}) failed for prompt interpretation: ` +
        `${firstError instanceof Error ? firstError.message : firstError}`,
    );
    try {
      content = await attempt("llama-3.3-70b-versatile");
    } catch (secondError) {
      throw new PromptInterpreterUnavailableError(
        secondError instanceof Error ? secondError.message : String(secondError),
      );
    }
  }

  try {
    const parsed = extractJson(content);
    return { theme: parsed.theme, category_keys: parsed.category_keys };
  } catch (error) {
    if (error instanceof JsonExtractionError) {
      throw new PromptInterpreterUnavailableError(`Unparseable response from Groq: ${error.message}`);
    }
    throw error;
  }
}
