/**
 * The `requests` shim. Node's global `fetch` covers everything the Python
 * server used, but not with the same ergonomics — this restores query-param
 * building, a per-request timeout, and `raise_for_status()`.
 *
 * `RequestError` stands in for `requests.RequestException`. Every call site in
 * the Python code caught it together with `ValueError` (a JSON decode failure),
 * so JSON parse failures are raised as `RequestError` too and the `except`
 * clauses port across one-to-one.
 */
import { Config } from "./config";

export class RequestError extends Error {
  readonly status?: number;
  readonly body?: string;

  constructor(message: string, options: { status?: number; body?: string; cause?: unknown } = {}) {
    super(message, { cause: options.cause });
    this.name = "RequestError";
    this.status = options.status;
    this.body = options.body;
  }
}

export type QueryParams = Record<string, string | number | boolean | undefined | null>;

export interface RequestOptions {
  params?: QueryParams;
  headers?: Record<string, string>;
  timeoutMs?: number;
  method?: string;
  /** Form-encoded body (Python's `data=`). */
  form?: Record<string, string>;
  /** JSON body (Python's `json=`). */
  json?: unknown;
  /**
   * Caller-owned cancellation, combined with the timeout. Used by the Overpass
   * hedging to drop mirrors whose answer is no longer wanted — something the
   * Python's `pool.shutdown(wait=False)` could not actually do.
   */
  signal?: AbortSignal;
}

/** `ai_tour_ingestion/1.0 (contact)` — the User-Agent every Wikimedia and
 * Overpass call is expected to identify itself with. */
export function userAgent(): string {
  const contact = Config.OVERPASS_CONTACT || "no-contact-configured";
  return `ai_tour_ingestion/1.0 (${contact})`;
}

function buildUrl(url: string, params?: QueryParams): string {
  if (!params) return url;
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null) continue;
    search.append(key, String(value));
  }
  const query = search.toString();
  if (!query) return url;
  return url + (url.includes("?") ? "&" : "?") + query;
}

/**
 * One HTTP round trip. Returns the raw `Response` — status is inspected by
 * several callers (404 means "no article", 429 means "throttled") before
 * `raiseForStatus` is applied, exactly as in the Python.
 */
export async function request(url: string, options: RequestOptions = {}): Promise<Response> {
  const { params, headers = {}, timeoutMs = 15_000, method, form, json, signal } = options;

  const timeoutSignal = AbortSignal.timeout(timeoutMs);
  const init: RequestInit = {
    method: method ?? (form || json !== undefined ? "POST" : "GET"),
    headers: { "User-Agent": userAgent(), ...headers },
    signal: signal ? AbortSignal.any([timeoutSignal, signal]) : timeoutSignal,
  };

  if (form) {
    init.body = new URLSearchParams(form);
  } else if (json !== undefined) {
    init.body = JSON.stringify(json);
    init.headers = { ...(init.headers as Record<string, string>), "Content-Type": "application/json" };
  }

  try {
    return await fetch(buildUrl(url, params), init);
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    throw new RequestError(`request to ${url} failed: ${reason}`, { cause: error });
  }
}

/** `resp.raise_for_status()`. */
export async function raiseForStatus(response: Response, url: string): Promise<void> {
  if (response.ok) return;
  let body = "";
  try {
    body = (await response.text()).slice(0, 500);
  } catch {
    /* the status is the useful part */
  }
  throw new RequestError(`${response.status} ${response.statusText} for ${url}`, {
    status: response.status,
    body,
  });
}

/** `resp.json()`, raising `RequestError` rather than `ValueError` on bad JSON. */
export async function parseJson<T = unknown>(response: Response, url: string): Promise<T> {
  try {
    return (await response.json()) as T;
  } catch (error) {
    throw new RequestError(`invalid JSON from ${url}`, { cause: error });
  }
}

/** `requests.get(...).raise_for_status(); return resp.json()` in one call. */
export async function getJson<T = unknown>(url: string, options: RequestOptions = {}): Promise<T> {
  const response = await request(url, { ...options, method: "GET" });
  await raiseForStatus(response, url);
  return parseJson<T>(response, url);
}
