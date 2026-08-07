import * as fs from "fs";
import * as path from "path";

import * as dotenv from "dotenv";

/**
 * backend/.env, not backend/server-node/.env — this app lives alongside
 * hunyuan2.1/ as a component of the same backend/ folder, and shares the one
 * env file with the Python server it replaces.
 *
 * `__dirname` is `<root>/src` under tsx and `<root>/dist` after a build, both
 * one level under the project root, so "../.." lands on backend/ either way.
 * The upward walk is a fallback for anyone running the compiled output from
 * somewhere unexpected.
 */
function findBackendDir(): string {
  const guess = path.resolve(__dirname, "../..");
  if (fs.existsSync(path.join(guess, ".env"))) return guess;

  let dir = __dirname;
  for (let i = 0; i < 6; i++) {
    if (fs.existsSync(path.join(dir, ".env"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return guess;
}

export const BACKEND_DIR = findBackendDir();

dotenv.config({ path: path.join(BACKEND_DIR, ".env") });

export const Config = {
  GROQ_API_KEY: process.env.GROQ_API_KEY,
  GEMINI_API_KEY: process.env.GEMINI_API_KEY,
  LLM_BASE_URL: process.env.LLM_BASE_URL ?? "https://api.groq.com/openai/v1",
  LLM_MODEL: process.env.LLM_MODEL ?? "qwen/qwen3.6-27b",

  // The anon key: this is what every *read* path uses (data/locationsRepo.ts).
  // RLS grants anon+authenticated select on the public catalogue and
  // nothing else — see docs/backend/02.
  SUPABASE_URL: process.env.SUPABASE_URL,
  SUPABASE_ANON_KEY: process.env.SUPABASE_ANON_KEY,

  // The service_role key: held only by this trusted server, used only by
  // the ingestion module (ingestion/supabaseAdmin.ts) to write newly
  // discovered POIs. Every write it performs still goes through narrow,
  // validated RPCs (upsert_ingested_location, upsert_poi_tile) rather than
  // raw table access — see docs/backend/12. Never let this reach the app.
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,

  OVERPASS_CONTACT: process.env.OVERPASS_CONTACT ?? "",

  PORT: Number.parseInt(process.env.PORT ?? "8000", 10),
  DEBUG: process.env.FLASK_DEBUG === "1",

  MODAL_PROXY_KEY: process.env.MODAL_PROXY_KEY,
  MODAL_PROXY_SECRET: process.env.MODAL_PROXY_SECRET,
  MODAL_SUBMIT_URL: process.env.MODAL_SUBMIT_URL,
} as const;

/**
 * Python's `RuntimeError`, which several routes catch by type to turn a
 * misconfiguration into a 503 rather than an opaque 500. TypeScript has no
 * equivalent built-in, so the distinction is carried by this class.
 */
export class ConfigurationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigurationError";
  }
}

export function requireLlmKey(): string {
  if (!Config.GROQ_API_KEY) {
    throw new ConfigurationError("GROQ_API_KEY is not set. Add it to backend/.env.");
  }
  return Config.GROQ_API_KEY;
}

export function requireGeminiKey(): string {
  if (!Config.GEMINI_API_KEY) {
    throw new ConfigurationError("GEMINI_API_KEY is not set. Add it to backend/.env.");
  }
  return Config.GEMINI_API_KEY;
}

export function requireServiceRoleKey(): string {
  if (!Config.SUPABASE_SERVICE_ROLE_KEY) {
    throw new ConfigurationError(
      "SUPABASE_SERVICE_ROLE_KEY is not set. Add it to backend/.env — " +
        "find it in the Supabase dashboard under Project Settings > API " +
        "(the 'service_role' secret key, not the anon/publishable one). " +
        "Only the POI ingestion pipeline needs this; every other route " +
        "works fine without it.",
    );
  }
  return Config.SUPABASE_SERVICE_ROLE_KEY;
}

export function requireModalKeys(): [string, string, string] {
  if (!(Config.MODAL_PROXY_KEY && Config.MODAL_PROXY_SECRET && Config.MODAL_SUBMIT_URL)) {
    throw new ConfigurationError(
      "MODAL_PROXY_KEY, MODAL_PROXY_SECRET, or MODAL_SUBMIT_URL is not set. " +
        "Add them to backend/.env to use the 3D generation endpoint.",
    );
  }
  return [Config.MODAL_PROXY_KEY, Config.MODAL_PROXY_SECRET, Config.MODAL_SUBMIT_URL];
}
