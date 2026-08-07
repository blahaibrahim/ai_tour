/**
 * Unicode-aware string helpers, and the one place the Latin/Arabic folding
 * lives.
 *
 * This is the highest-risk file in the port, because Python's string methods
 * are Unicode-aware by default and JavaScript's are not. Three specific traps
 * the rest of the code relies on being handled here:
 *
 *   * `str.isalnum()` is `\p{L}` ∪ `\p{N}`, not `[a-z0-9]`.
 *   * `\w` in a Python pattern matches Arabic and accented Latin; in
 *     JavaScript it is ASCII-only unless you write `\p{L}` with the `u` flag.
 *   * `str.capitalize()` lowercases everything after the first character, and
 *     `str.title()` treats digits and punctuation as word boundaries.
 *
 * Getting any of these subtly wrong degrades photo matching and dedup silently
 * rather than loudly, which is why `testPoiRules.ts` pins them.
 */

/**
 * Fold to a comparable form: strip Latin accents, apply the standard Arabic
 * orthographic normalizations (alef/teh-marbuta/alef-maksura variants,
 * tatweel), lowercase, and reduce punctuation to spaces.
 *
 * `ingestion/overpass.ts` and `ingestion/photos.ts` both need exactly this and
 * the Python kept two identical copies (each documented as "same folding as
 * the other"); here it is shared.
 *
 * The Arabic folding is not cosmetic — OSM and Commons routinely disagree on
 * أ vs ا in the same name, which would otherwise defeat token matching.
 *
 * Note on `\p{M}` vs Python's `unicodedata.combining()`: they differ only for
 * spacing marks with a zero combining class (Devanagari matras and the like),
 * which cannot appear in the Latin/Arabic data this pipeline handles.
 */
export function normalizeFold(text: string | null | undefined): string {
  let out = (text ?? "").normalize("NFKD");
  out = out.replace(/\p{M}/gu, "");
  out = out.toLowerCase();
  out = out.replace(/[أإآٱ]/gu, "ا");
  out = out.replace(/ة/gu, "ه").replace(/ى/gu, "ي").replace(/ـ/gu, "");
  return Array.from(out)
    .map((char) => (/[\p{L}\p{N}]/u.test(char) ? char : " "))
    .join("");
}

/** Python's `str.split()` — split on any run of whitespace, no empty pieces. */
export function words(text: string): string[] {
  return text.split(/\s+/u).filter((word) => word.length > 0);
}

/** Python's `" ".join(text.split())` — collapse all whitespace runs to one space. */
export function collapseWhitespace(text: string): string {
  return words(text).join(" ");
}

/** Python's `str.capitalize()`: first character up, everything after it down. */
export function capitalize(text: string): string {
  if (!text) return text;
  const chars = Array.from(text);
  return chars[0].toUpperCase() + chars.slice(1).join("").toLowerCase();
}

/**
 * Python's `str.title()`: each run of letters gets its first character
 * uppercased and the rest lowercased, with digits and punctuation acting as
 * word boundaries ("don't" -> "Don'T", "a1b" -> "A1B").
 */
export function titleCase(text: string): string {
  return text.replace(/\p{L}+/gu, (word) => {
    const chars = Array.from(word);
    return chars[0].toUpperCase() + chars.slice(1).join("").toLowerCase();
  });
}

/** Count of characters Python's `str.isalpha()` accepts. */
export function countLetters(text: string): number {
  return (text.match(/\p{L}/gu) ?? []).length;
}

/** Count of characters Python's `str.isdigit()` accepts. */
export function countDigits(text: string): number {
  return (text.match(/\p{Nd}/gu) ?? []).length;
}

/**
 * `round(value, digits)`. Python rounds halves to even and JavaScript rounds
 * them away from zero, so a value landing exactly on a half can differ in the
 * last decimal place. Every use here is a displayed distance or a cache key,
 * where that is immaterial.
 */
export function roundTo(value: number, digits = 0): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

/** `urllib.parse.unquote` — permissive, unlike `decodeURIComponent`. */
export function unquote(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    // Python's unquote leaves malformed escapes alone rather than raising.
    return value;
  }
}

// --- set operations, for the token matching in photos.ts and overpass.ts ----

export function intersects<T>(a: ReadonlySet<T>, b: ReadonlySet<T>): boolean {
  const [small, large] = a.size <= b.size ? [a, b] : [b, a];
  for (const item of small) if (large.has(item)) return true;
  return false;
}

export function intersection<T>(a: ReadonlySet<T>, b: ReadonlySet<T>): Set<T> {
  const [small, large] = a.size <= b.size ? [a, b] : [b, a];
  const out = new Set<T>();
  for (const item of small) if (large.has(item)) out.add(item);
  return out;
}

/** Python's `a <= b` on sets. */
export function isSubsetOf<T>(a: ReadonlySet<T>, b: ReadonlySet<T>): boolean {
  if (a.size > b.size) return false;
  for (const item of a) if (!b.has(item)) return false;
  return true;
}

export function unionInto<T>(target: Set<T>, source: Iterable<T>): Set<T> {
  for (const item of source) target.add(item);
  return target;
}

/**
 * Lexicographic comparison of two tuples of numbers, for porting Python's
 * `sorted(key=lambda x: (a, b, c))`.
 */
export function compareTuples(a: readonly number[], b: readonly number[]): number {
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const left = a[i] ?? 0;
    const right = b[i] ?? 0;
    if (left !== right) return left < right ? -1 : 1;
  }
  return 0;
}
