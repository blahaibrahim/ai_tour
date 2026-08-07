import { GoogleGenAI } from "@google/genai";
import OpenAI from "openai";

import { Config, requireGeminiKey, requireLlmKey } from "./config";
import { extractJson } from "./jsonUtils";
import { getLogger } from "./logger";
import { ChatMessage } from "./types";

const logger = getLogger("llm");

let groqClient: OpenAI | null = null;
let geminiClient: GoogleGenAI | null = null;

export class LLMError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LLMError";
  }
}

export function getGroqClient(): OpenAI {
  if (groqClient === null) {
    groqClient = new OpenAI({ baseURL: Config.LLM_BASE_URL, apiKey: requireLlmKey() });
  }
  return groqClient;
}

export function getGeminiClient(): GoogleGenAI {
  if (geminiClient === null) {
    geminiClient = new GoogleGenAI({ apiKey: requireGeminiKey() });
  }
  return geminiClient;
}

const GEMINI_MODEL = "models/gemini-3-flash-preview";
const GEMINI_EMBED_MODEL = "models/gemini-embedding-2";

/**
 * The Python called `client.interactions.create(..., generation_config={
 * 'thinking_level': ...})`. The JS SDK's equivalent surface is
 * `models.generateContent` with `config.thinkingConfig.thinkingLevel`, and
 * whether that field is accepted depends on the installed SDK version.
 *
 * A rejected field must not cost us the provider permanently *or* be retried
 * on every call, so the first "unknown field" style failure flips this flag and
 * every later call goes straight to the plain config. Any other failure falls
 * through to `chat`'s existing Groq fallback, exactly as before.
 */
let thinkingLevelSupported = true;

interface GeminiOptions {
  jsonMode: boolean;
  maxTokens: number;
  temperature: number;
  thinkingLevel: string;
}

function looksLikeUnknownFieldError(error: unknown): boolean {
  const message = (error instanceof Error ? error.message : String(error)).toLowerCase();
  return (
    message.includes("thinking") ||
    message.includes("unknown field") ||
    message.includes("unknown name") ||
    message.includes("invalid json payload")
  );
}

async function generateContent(
  prompt: string,
  config: Record<string, unknown>,
): Promise<string> {
  const client = getGeminiClient();
  const response = await client.models.generateContent({
    model: GEMINI_MODEL,
    contents: prompt,
    config: config as never,
  });
  return response.text ?? "";
}

async function chatGemini(messages: ChatMessage[], options: GeminiOptions): Promise<string> {
  const { jsonMode, maxTokens, temperature, thinkingLevel } = options;

  let prompt = messages.map((m) => `${m.role.toUpperCase()}: ${m.content}`).join("\n");
  if (jsonMode) {
    prompt += "\n\nCRITICAL INSTRUCTION: Return ONLY valid JSON.";
  }

  const baseConfig: Record<string, unknown> = {
    // Headroom for reasoning, but bounded by the caller's own budget — an
    // unconditional 65536 lets a model that starts rambling run for a
    // minute before anything stops it.
    maxOutputTokens: Math.max(maxTokens * 4, 4096),
    temperature,
  };
  if (jsonMode) {
    baseConfig.responseMimeType = "application/json";
  }

  let content: string;
  if (thinkingLevelSupported) {
    try {
      content = await generateContent(prompt, {
        ...baseConfig,
        thinkingConfig: { thinkingLevel },
      });
    } catch (error) {
      if (!looksLikeUnknownFieldError(error)) throw error;
      logger.warning(
        "Gemini rejected thinkingLevel; disabling it for the rest of this process:",
        error instanceof Error ? error.message : error,
      );
      thinkingLevelSupported = false;
      content = await generateContent(prompt, baseConfig);
    }
  } else {
    content = await generateContent(prompt, baseConfig);
  }

  if (!content) {
    throw new LLMError("Empty response from Gemini");
  }

  // Optional: strip markdown json blocks if present
  if (jsonMode) {
    content = content.trim();
    if (content.startsWith("```json")) content = content.slice(7);
    if (content.startsWith("```")) content = content.slice(3);
    if (content.endsWith("```")) content = content.slice(0, -3);
  }

  return content.trim();
}

export interface ChatOptions {
  jsonMode?: boolean;
  maxTokens?: number;
  temperature?: number;
  thinkingLevel?: string;
  prefer?: "gemini" | "groq";
}

/**
 * Send a chat-completion request. Both providers back each other up;
 * `prefer` picks which one is tried first.
 *
 * Two latency dials, both measured on the itinerary selection prompt
 * (pick 8 ids out of 30 candidates, JSON out):
 *
 *   * `thinkingLevel` — 'minimal' 5.5s, 'low' 16.2s, 'medium' 16.1s,
 *     'high' 20.6s, all returning the same 8 valid ids. It was hardcoded to
 *     'medium' for every caller, so a constrained selection over pre-vetted
 *     candidates was paying full reasoning cost for nothing.
 *   * `prefer` — Groq answers the same prompt in ~1.6s against Gemini's 5.5s
 *     at its fastest. Gemini stays the default (it is the better model for
 *     the open-ended describe/rewrite work), but latency-critical calls on
 *     the user's waiting path ask for Groq first and still fall back to
 *     Gemini if Groq is down. Nothing loses a provider; only the order
 *     changes.
 */
export async function chat(messages: ChatMessage[], options: ChatOptions = {}): Promise<string> {
  const {
    jsonMode = false,
    maxTokens = 800,
    temperature = 0.7,
    thinkingLevel = "medium",
    prefer = "gemini",
  } = options;

  const geminiOptions: GeminiOptions = { jsonMode, maxTokens, temperature, thinkingLevel };

  if (prefer === "gemini") {
    try {
      return await chatGemini(messages, geminiOptions);
    } catch (error) {
      logger.info(
        `Gemini failed, falling back to Groq: ${error instanceof Error ? error.message : error}`,
      );
    }
  }

  // Groq — either the caller's preference, or Gemini's fallback.
  const client = getGroqClient();
  const baseParams: Record<string, unknown> = {
    model: Config.LLM_MODEL,
    messages,
    max_tokens: maxTokens,
    temperature,
  };

  const withExtras: Record<string, unknown> = { ...baseParams, reasoning_effort: "none" };
  if (jsonMode) {
    withExtras.response_format = { type: "json_object" };
  }

  const create = (params: Record<string, unknown>): Promise<OpenAI.Chat.ChatCompletion> =>
    client.chat.completions.create(
      params as unknown as OpenAI.Chat.ChatCompletionCreateParamsNonStreaming,
    );

  const isApiError = (error: unknown): boolean => error instanceof OpenAI.APIError;

  let response: OpenAI.Chat.ChatCompletion;
  try {
    response = await create(withExtras);
  } catch (firstError) {
    if (!isApiError(firstError)) throw firstError;
    try {
      response = await create(baseParams);
    } catch (secondError) {
      if (!isApiError(secondError)) throw secondError;
      logger.error(
        `Groq primary model (${Config.LLM_MODEL}) failed: ` +
          `${secondError instanceof Error ? secondError.message : secondError}`,
      );
      try {
        // Try a guaranteed Groq model if the configured one fails
        response = await create({ ...baseParams, model: "llama-3.3-70b-versatile" });
      } catch (thirdError) {
        if (!isApiError(thirdError)) throw thirdError;
        logger.error(
          `Groq fallback model failed: ` +
            `${thirdError instanceof Error ? thirdError.message : thirdError}`,
        );
        if (prefer === "groq") {
          // Groq was first choice, so Gemini hasn't been tried yet —
          // a preference must not cost the caller a provider.
          logger.info("Groq exhausted, falling back to Gemini");
          return chatGemini(messages, geminiOptions);
        }
        throw new LLMError(thirdError instanceof Error ? thirdError.message : String(thirdError));
      }
    }
  }

  const content = response.choices[0]?.message?.content;
  if (!content) {
    throw new LLMError("Empty response from the LLM provider");
  }
  return content;
}

/** Generate a vector embedding for a piece of text using Gemini. */
export async function embed(text: string): Promise<number[]> {
  try {
    const client = getGeminiClient();
    const response = await client.models.embedContent({
      model: GEMINI_EMBED_MODEL,
      contents: text,
      config: { outputDimensionality: 384 },
    });
    const values = response.embeddings?.[0]?.values;
    if (!values) throw new Error("no embedding returned");
    return values;
  } catch (error) {
    logger.error(`Gemini embed failed: ${error instanceof Error ? error.message : error}`);
    // Note: Groq doesn't provide embeddings, so if Gemini fails we raise.
    throw new LLMError(`Embedding failed: ${error instanceof Error ? error.message : error}`);
  }
}

export interface Intent {
  themes: Array<{ name: string; weight: number }>;
  activities: string[];
  required_categories: string[];
  preferred_categories: string[];
  excluded_categories: string[];
}

const EMPTY_INTENT: Intent = {
  themes: [],
  activities: [],
  required_categories: [],
  preferred_categories: [],
  excluded_categories: [],
};

/** Extract structured intent from a user's travel prompt using Gemini. */
export async function extractIntent(prompt: string): Promise<Intent> {
  const inputPrompt =
    "Analyze this travel prompt and extract the requested themes, activities, and category preferences. " +
    "Return ONLY a valid JSON object matching this schema:\n" +
    "{\n" +
    '  "themes": [{"name": "string", "weight": 1.0}],\n' +
    '  "activities": ["string"],\n' +
    '  "required_categories": ["string"],\n' +
    '  "preferred_categories": ["string"],\n' +
    '  "excluded_categories": ["string"]\n' +
    "}\n\n" +
    `Prompt: ${prompt}`;

  const config: Record<string, unknown> = {
    temperature: 1,
    maxOutputTokens: 65536,
    topP: 0.95,
  };
  if (thinkingLevelSupported) {
    config.thinkingConfig = { thinkingLevel: "high" };
  }

  try {
    const raw = await generateContent(inputPrompt, config);
    return { ...EMPTY_INTENT, ...(extractJson(raw) as Partial<Intent>) };
  } catch (error) {
    logger.error(`Intent extraction failed: ${error instanceof Error ? error.message : error}`);
    return { ...EMPTY_INTENT };
  }
}
