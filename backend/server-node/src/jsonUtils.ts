/**
 * Defensive JSON parsing for LLM output.
 *
 * Models behind a router sometimes wrap JSON in markdown fences or add stray
 * prose despite being told not to. Try a straight parse first, then salvage a
 * fenced or embedded object before giving up.
 */

/** Python's `ValueError`, which the routes catch to answer 502 llm_bad_output. */
export class JsonExtractionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JsonExtractionError";
  }
}

function tryParse(text: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(text);
    // `json.loads` would happily return a list or a number; every caller here
    // immediately does `.get(...)`, so only an object is a usable answer.
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
    return null;
  } catch {
    return null;
  }
}

export function extractJson(text: string): Record<string, unknown> {
  const direct = tryParse(text);
  if (direct) return direct;

  // Non-greedy, matching Python's `\{.*?\}` with re.DOTALL.
  const fenced = /```(?:json)?\s*(\{[\s\S]*?\})\s*```/.exec(text);
  if (fenced) {
    const parsed = tryParse(fenced[1]);
    if (parsed) return parsed;
  }

  // Greedy, matching Python's `\{.*\}` with re.DOTALL — the outermost braces.
  const brace = /\{[\s\S]*\}/.exec(text);
  if (brace) {
    const parsed = tryParse(brace[0]);
    if (parsed) return parsed;
  }

  throw new JsonExtractionError("Could not parse a JSON object out of the LLM response");
}
