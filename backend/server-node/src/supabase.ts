/**
 * The one behavioural difference between supabase-py and supabase-js that
 * matters for this port: Python raises on a failed query, JavaScript returns
 * `{ data: null, error }`. Every `try/except` in the Flask code was written
 * against the raising version, so `unwrap` restores it and the control flow
 * ports across unchanged.
 *
 * The second difference is quieter and easier to get wrong: `insert()` and
 * `upsert()` return the written rows by default in supabase-py, but return
 * `null` in supabase-js unless `.select()` is chained. Every call site here
 * that reads back an id chains `.select()` for that reason.
 *
 * Note on typing: the row types are supplied by the caller as `T`, not
 * inferred, because this project has no generated `Database` type — without
 * one, supabase-js widens any `select()` carrying an embedded relation to
 * `GenericStringError[]`. Running `supabase gen types typescript` and passing
 * the result to `createClient<Database>` would make these annotations checked
 * rather than asserted; that is the natural next step and the only reason
 * `as T` appears below.
 */

export class SupabaseError extends Error {
  readonly details?: string;
  readonly code?: string;

  constructor(message: string, options: { details?: string; code?: string } = {}) {
    super(message);
    this.name = "SupabaseError";
    this.details = options.details;
    this.code = options.code;
  }
}

/** Just enough shape to cover every builder supabase-js resolves to. */
interface AnySupabaseResult {
  data: unknown;
  error: unknown;
}

function toSupabaseError(error: unknown): SupabaseError {
  if (error && typeof error === "object") {
    const e = error as { message?: unknown; details?: unknown; code?: unknown };
    return new SupabaseError(
      typeof e.message === "string" ? e.message : JSON.stringify(error),
      {
        details: typeof e.details === "string" ? e.details : undefined,
        code: typeof e.code === "string" ? e.code : undefined,
      },
    );
  }
  return new SupabaseError(String(error));
}

/** Await a supabase-js query and raise on error, the way supabase-py does. */
export async function unwrap<T>(query: PromiseLike<AnySupabaseResult>): Promise<T | null> {
  const { data, error } = await query;
  if (error) {
    throw toSupabaseError(error);
  }
  return (data ?? null) as T | null;
}

/** `unwrap` for queries that must return rows; `[]` rather than `null`. */
export async function unwrapRows<T>(query: PromiseLike<AnySupabaseResult>): Promise<T[]> {
  return (await unwrap<T[]>(query)) ?? [];
}
