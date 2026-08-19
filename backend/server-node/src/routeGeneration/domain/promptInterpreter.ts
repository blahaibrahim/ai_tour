/**
 * Layer 3 — Prompt Interpreter.
 *
 * Turns free text into a theme plus preferred categories, grounded against
 * what the requested city can actually answer. This is the enforcement
 * point: `adapters/promptInterpreterAdapter.ts` returns whatever Groq said,
 * untrusted, and every key that leaves this file has been checked against a
 * real vocabulary the caller supplied. Nothing downstream re-checks this.
 *
 * ## Why categories are a preference, not a filter
 *
 * The obvious design — intersect the model's category_keys with the theme's
 * set the way `poiSelector.selectPois` does for the request builder's chips
 * — was rejected. A chip tap is the traveller looking at a fixed list and
 * choosing to exclude everything else; "show me beaches" in a sentence is
 * not that. It is one thing the traveller wants *more* of, said alongside
 * however much else they didn't bother to mention. Treating it as a hard
 * filter turns "beaches, mostly" into "beaches, only", which is a stronger
 * claim than the sentence made and the reason a real city can 422 on a
 * perfectly answerable prompt. So `PromptInterpretation.categoryKeys` is
 * carried into `RouteRequest.preferredCategoryKeys` and only ever biases
 * ranking — see `domain/budgetFitter.ts`'s preference boost.
 *
 * ## Why the theme still gets validated as a member, not a preference
 *
 * A theme selects which category set is even in play (`categoriesForTheme`);
 * there is no softer reading of "history" that still means something once it
 * stops picking a category set. So a theme candidate that is not in the
 * city's `themes_available` list is dropped outright rather than downgraded.
 *
 * ## No hard failure mode
 *
 * Every exit from `interpret` is a 200-shaped answer. A Groq outage and "the
 * traveller wrote something with no recognisable place in it" are the same
 * case from the route's point of view: nothing to prefer, generate the
 * theme's full set as before. Themes stay optional end to end, so there is
 * nothing here for a 4xx or 5xx to be about — see `routes/routes.ts`'s
 * `/api/routes/interpret` handler for the actual failure modes (bad city id,
 * empty prompt), which are request-shape problems, not interpretation ones.
 */
import { getLogger } from "../../logger";
import {
  InterpretPromptInput,
  interpretPromptRaw,
  PromptInterpreterUnavailableError,
  VocabularyCategory,
  VocabularyTheme,
} from "../adapters/promptInterpreterAdapter";
import { PromptInterpretation } from "../types";

const logger = getLogger("routeGeneration.promptInterpreter");

const EMPTY: PromptInterpretation = { theme: null, categoryKeys: [], understood: false };

export interface InterpretInput {
  prompt: string;
  locale: InterpretPromptInput["locale"];
  themes: VocabularyTheme[];
  categories: VocabularyCategory[];
}

export interface PromptInterpreterDeps {
  /** Resolves a theme to the category keys it covers in this city — the same
   * source `poiSelector.categoriesForTheme` reads, injected so this module
   * can be unit-tested as a pure function of its inputs. */
  categoriesForTheme: (themeKey: string) => Promise<string[]>;
  /** The Groq call. Defaults to the real adapter; overridden in tests
   * (`testRouteGeneration.ts`) with a canned responder so the validation,
   * retry and reconciliation logic can run with no network and no key. */
  interpretRaw?: typeof interpretPromptRaw;
}

function normalise(key: unknown): string | null {
  if (typeof key !== "string") return null;
  const trimmed = key.trim().toLowerCase();
  return trimmed.length > 0 ? trimmed : null;
}

/** The raw strings in `raw` that were not accepted — kept so a retry can be
 * told specifically what it invented, rather than just "try again". */
function rawStrings(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter((v): v is string => typeof v === "string");
}

/** Keeps only the entries in `raw` that name a real key in `valid`, case- and
 * whitespace-insensitively. Anything else — a hallucinated key, a number, a
 * nested object — is silently dropped: a partially unusable answer is still
 * a usable one, and surfacing the drop to the traveller would explain
 * nothing they could act on. */
function validCategoryKeys(raw: unknown, valid: ReadonlySet<string>): string[] {
  if (!Array.isArray(raw)) return [];
  const kept = new Set<string>();
  for (const entry of raw) {
    const key = normalise(entry);
    if (key && valid.has(key)) kept.add(key);
  }
  return [...kept];
}

function validTheme(raw: unknown, valid: ReadonlySet<string>): string | null {
  const key = normalise(raw);
  return key && valid.has(key) ? key : null;
}

interface Attempt {
  theme: string | null;
  categoryKeys: string[];
  /** Everything the model returned in `category_keys` before validation —
   * used only to build the retry's "these don't exist" message. */
  rawCategoryStrings: string[];
}

/** Runs one Groq call and validates whatever comes back. Never throws — a
 * provider failure is reported the same as "nothing survived validation",
 * since both mean this attempt has nothing usable. */
async function attempt(
  input: InterpretPromptInput,
  themeKeys: ReadonlySet<string>,
  categoryKeys: ReadonlySet<string>,
  callRaw: typeof interpretPromptRaw,
): Promise<Attempt> {
  try {
    const raw = await callRaw(input);
    return {
      theme: validTheme(raw.theme, themeKeys),
      categoryKeys: validCategoryKeys(raw.category_keys, categoryKeys),
      rawCategoryStrings: rawStrings(raw.category_keys),
    };
  } catch (error) {
    if (error instanceof PromptInterpreterUnavailableError) {
      logger.warning(`Groq unavailable for prompt interpretation: ${error.message}`);
      return { theme: null, categoryKeys: [], rawCategoryStrings: [] };
    }
    throw error;
  }
}

/**
 * If the surviving categories don't belong to the surviving theme (or there
 * is no theme yet), re-derives the theme from the categories instead of
 * leaving the two in conflict. Categories win the tie-break: naming "museums
 * and viewpoints" is a more specific signal than a theme word. `themeCategories`
 * covers only the themes actually offered for this city, so this never
 * proposes a theme the city can't route.
 */
function reconcileTheme(
  theme: string | null,
  categoryKeys: string[],
  themeCategories: ReadonlyMap<string, ReadonlySet<string>>,
): string | null {
  if (categoryKeys.length === 0) return theme;

  const currentScore = theme
    ? categoryKeys.filter((k) => themeCategories.get(theme)?.has(k)).length
    : -1;
  if (theme && currentScore === categoryKeys.length) return theme; // every key already fits

  let best = theme;
  let bestScore = currentScore;
  for (const [candidate, categories] of themeCategories) {
    const score = categoryKeys.filter((k) => categories.has(k)).length;
    if (score > bestScore) {
      best = candidate;
      bestScore = score;
    }
  }
  // Only override when some theme actually covers at least one of the
  // categories — an unrecognised theme name should not be replaced by a
  // worse guess just because nothing scored above -1.
  return bestScore > 0 ? best : theme;
}

/**
 * Interprets one prompt against `input`'s vocabulary, reconciled so the
 * returned theme is never in conflict with the returned categories.
 *
 * One retry: if the first pass returns neither a valid theme nor any valid
 * category but the model *did* try to name categories, a second call runs
 * telling it which keys don't exist. Two failures in a row — or a first pass
 * that named nothing at all — is treated as a signal about the prompt (or
 * about Groq being down), not something a third attempt fixes; the caller
 * gets back `EMPTY` and the route generates unnarrowed, same as if the
 * traveller had typed nothing.
 */
export async function interpret(
  input: InterpretInput,
  deps: PromptInterpreterDeps,
): Promise<PromptInterpretation> {
  const prompt = input.prompt.trim();
  if (!prompt) return EMPTY;

  const themeKeys = new Set(input.themes.map((t) => t.key.toLowerCase()));
  const categoryKeySet = new Set(input.categories.map((c) => c.key.toLowerCase()));
  if (themeKeys.size === 0 && categoryKeySet.size === 0) return EMPTY;

  const base: InterpretPromptInput = {
    prompt,
    locale: input.locale,
    themes: input.themes,
    categories: input.categories,
  };

  const callRaw = deps.interpretRaw ?? interpretPromptRaw;

  let result = await attempt(base, themeKeys, categoryKeySet, callRaw);

  if (result.theme === null && result.categoryKeys.length === 0 && result.rawCategoryStrings.length > 0) {
    result = await attempt(
      { ...base, rejectedKeys: result.rawCategoryStrings },
      themeKeys,
      categoryKeySet,
      callRaw,
    );
  }

  if (result.theme === null && result.categoryKeys.length === 0) return EMPTY;

  const themeCategories = new Map<string, ReadonlySet<string>>();
  for (const t of input.themes) {
    themeCategories.set(t.key, new Set(await deps.categoriesForTheme(t.key)));
  }

  return {
    theme: reconcileTheme(result.theme, result.categoryKeys, themeCategories),
    categoryKeys: result.categoryKeys,
    understood: true,
  };
}
