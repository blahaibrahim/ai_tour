import {
  SIGNED_URL_TTL_SECONDS,
  SUPABASE_SERVICE_ROLE_KEY,
  SUPABASE_URL,
} from "./config";

/**
 * A dependency-free Supabase reader: PostgREST over `fetch`, plus the one
 * Storage endpoint this dashboard needs.
 *
 * No `@supabase/supabase-js`. Everything here is a GET against PostgREST and a
 * POST to sign object URLs — a client library would be a dependency added to
 * call `fetch` with two headers. It also keeps the boundary obvious: this
 * module is the only place the service-role key is read, and nothing in it
 * writes.
 *
 * Every read degrades to empty instead of throwing, and records why. One
 * unavailable table should grey out one card, not blank the page.
 */

export function supabaseConfigured(): boolean {
  return Boolean(SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY);
}

export const SUPABASE_HINT =
  "set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env.local " +
  "(Supabase dashboard > Project Settings > API). Everything sourced from the " +
  "database stays blank without them.";

export interface BucketUsage {
  bucket: string;
  objects: number;
  bytes: number;
}

export interface Reader {
  /**
   * One PostgREST select. `params` is passed through verbatim, so callers
   * write PostgREST syntax (`select`, `order`, `limit`, filters) rather than a
   * query builder that would only ever be used for these few reads.
   */
  select<T>(table: string, params?: Record<string, string>): Promise<T[]>;
  /** Row count without the rows. */
  count(table: string, params?: Record<string, string>): Promise<number>;
  /** Signed URLs for private-bucket objects, one round trip per bucket. */
  signUrls(bucket: string, paths: string[]): Promise<Map<string, string>>;
  /** Object count and total bytes per bucket. */
  storageUsage(): Promise<BucketUsage[]>;
  /** Everything that failed during this reader's lifetime. */
  errors(): string[];
}

/**
 * A reader scoped to one request.
 *
 * Scoped rather than module-level so two route handlers running at once cannot
 * take each other's errors — the warning a page shows is always about the read
 * that page actually did.
 */
export function reader(): Reader {
  const failures: string[] = [];
  const record = (what: string, err: unknown) =>
    failures.push(`${what}: ${(err as Error).message}`);

  const headers = {
    apikey: SUPABASE_SERVICE_ROLE_KEY,
    authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
    accept: "application/json",
  };

  async function get(
    table: string,
    params: Record<string, string>,
    extra: Record<string, string> = {},
  ): Promise<Response> {
    const query = new URLSearchParams(params).toString();
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/${table}${query ? `?${query}` : ""}`,
      {
        headers: { ...headers, ...extra },
        // Analytics that silently served a cached count would be worse than
        // slow ones, and every caller is behind `dynamic = "force-dynamic"`.
        cache: "no-store",
      },
    );
    if (!response.ok) {
      throw new Error(
        `${response.status} ${(await response.text()).slice(0, 180)}`,
      );
    }
    return response;
  }

  return {
    async select<T>(table: string, params: Record<string, string> = {}) {
      if (!supabaseConfigured()) return [] as T[];
      try {
        return (await (await get(table, params)).json()) as T[];
      } catch (err) {
        record(table, err);
        return [] as T[];
      }
    },

    async count(table: string, params: Record<string, string> = {}) {
      if (!supabaseConfigured()) return 0;
      try {
        // `count=exact` with one row asked for: PostgREST answers in the
        // Content-Range header, so a table with 50k captures gets counted
        // without pulling 50k captures across the wire. `select=*` rather than
        // a named column because several of these tables are join tables with
        // a composite key and no `id` at all.
        const response = await get(
          table,
          { ...params, select: "*", limit: "1" },
          { prefer: "count=exact" },
        );
        // "0-0/1234", or "*/1234" when the range is unsatisfiable.
        const total = response.headers.get("content-range")?.split("/")[1];
        return Number(total ?? 0) || 0;
      } catch (err) {
        record(table, err);
        return 0;
      }
    },

    async signUrls(bucket: string, paths: string[]) {
      const signed = new Map<string, string>();
      const wanted = [...new Set(paths.filter(Boolean))];
      if (!supabaseConfigured() || wanted.length === 0) return signed;

      try {
        // The capture, model and thumbnail buckets are private, so a storage
        // path out of the database is not something the browser can fetch.
        // Signing on render beats proxying the bytes through this server.
        const response = await fetch(
          `${SUPABASE_URL}/storage/v1/object/sign/${bucket}`,
          {
            method: "POST",
            headers: { ...headers, "content-type": "application/json" },
            body: JSON.stringify({
              expiresIn: SIGNED_URL_TTL_SECONDS,
              paths: wanted,
            }),
            cache: "no-store",
          },
        );
        if (!response.ok) throw new Error(`${response.status}`);

        const rows = (await response.json()) as {
          path: string | null;
          signedURL: string | null;
          error: string | null;
        }[];
        for (const row of rows) {
          // A missing object is reported per row rather than failing the
          // batch — one deleted capture shouldn't blank its neighbours.
          if (row.path && row.signedURL && !row.error) {
            signed.set(row.path, `${SUPABASE_URL}/storage/v1${row.signedURL}`);
          }
        }
      } catch (err) {
        record(`storage/${bucket}`, err);
      }
      return signed;
    },

    async storageUsage() {
      if (!supabaseConfigured()) return [];
      try {
        // `storage.objects` carries each object's size in its metadata, so one
        // select over it beats paginating /storage/v1/object/list per user
        // folder per bucket. It needs `storage` added to the project's exposed
        // schemas (API Settings > Data API); when it is not, this is the one
        // card that stays empty.
        const rows = (await (
          await get(
            "objects",
            { select: "bucket_id,metadata", limit: "20000" },
            { "accept-profile": "storage" },
          )
        ).json()) as { bucket_id: string; metadata: { size?: number } | null }[];

        const usage = new Map<string, BucketUsage>();
        for (const row of rows) {
          const entry = usage.get(row.bucket_id) ?? {
            bucket: row.bucket_id,
            objects: 0,
            bytes: 0,
          };
          entry.objects += 1;
          entry.bytes += Number(row.metadata?.size ?? 0) || 0;
          usage.set(row.bucket_id, entry);
        }
        return [...usage.values()].sort((a, b) => b.bytes - a.bytes);
      } catch {
        // Not recorded as a failure: a project that has not exposed the
        // `storage` schema is the default, not a fault, and the card that
        // renders this says so. Everything else on the page is unaffected.
        return [];
      }
    },

    errors: () => [...new Set(failures)],
  };
}

/**
 * Sign a batch of `bucket/key` paths, grouped by bucket.
 *
 * The app stores storage references bucket-qualified — `captures/<user>/<id>.jpg`,
 * `models/<user>/<id>.glb` — while the sign endpoint takes the bucket in the
 * URL and the key in the body. Splitting on the first slash is what turns one
 * into the other; passing the stored string straight through signs a key that
 * does not exist and quietly returns nothing.
 */
export async function signStoragePaths(
  db: Reader,
  paths: (string | null | undefined)[],
): Promise<Map<string, string>> {
  const byBucket = new Map<string, string[]>();
  for (const path of paths) {
    if (!path) continue;
    const slash = path.indexOf("/");
    if (slash <= 0) continue;
    const bucket = path.slice(0, slash);
    byBucket.set(bucket, [...(byBucket.get(bucket) ?? []), path.slice(slash + 1)]);
  }

  const signed = new Map<string, string>();
  await Promise.all(
    [...byBucket.entries()].map(async ([bucket, keys]) => {
      for (const [key, url] of await db.signUrls(bucket, keys)) {
        signed.set(`${bucket}/${key}`, url);
      }
    }),
  );
  return signed;
}

/**
 * PostGIS point -> `{ lat, lon }`.
 *
 * PostgREST hands a `geography` column back the way Postgres renders it: hex
 * EWKB, e.g. `0101000020E6100000…`. That is a byte-order flag, a type word
 * with the SRID bit set, the SRID, then X and Y as little-endian doubles —
 * decoded here rather than by adding a view or an RPC to the schema, because
 * this dashboard has no business changing the app's database.
 *
 * GeoJSON objects are accepted too, in case the project is ever configured to
 * emit them.
 */
export function decodePoint(value: unknown): { lat: number; lon: number } | null {
  if (value && typeof value === "object") {
    const coords = (value as { coordinates?: unknown }).coordinates;
    if (!Array.isArray(coords) || coords.length < 2) return null;
    const [lon, lat] = coords as number[];
    return Number.isFinite(lat) && Number.isFinite(lon) ? { lat, lon } : null;
  }
  if (typeof value !== "string" || !/^[0-9a-fA-F]{42,}$/.test(value)) return null;

  const bytes = Uint8Array.from(
    value.match(/../g)!.map((pair) => parseInt(pair, 16)),
  );
  const view = new DataView(bytes.buffer);
  const little = bytes[0] === 1;
  const type = view.getUint32(1, little);
  // Low byte is the geometry type; 1 is Point. Anything else (a polygon, a
  // collection) is not something this dashboard knows how to place.
  if ((type & 0xff) !== 1) return null;

  const hasSrid = (type & 0x20000000) !== 0;
  const at = 5 + (hasSrid ? 4 : 0);
  if (bytes.length < at + 16) return null;

  const lon = view.getFloat64(at, little);
  const lat = view.getFloat64(at + 8, little);
  return Number.isFinite(lat) && Number.isFinite(lon) ? { lat, lon } : null;
}
