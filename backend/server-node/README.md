# ai_tour server — TypeScript

A port of [`backend/server`](../server) (Flask) to Node + TypeScript, plus the
skeleton of the new Route Generation module that replaces the old itinerary
endpoints.

Everything except route generation kept its HTTP contract exactly, so those
routes can be run side by side against the Flask server and diffed. Route
generation is a deliberate break — see below.

```sh
npm install
npm run dev        # tsx watch, port 8000
npm run build && npm start
npm test           # POI rule regressions, no network
npm run typecheck
```

Configuration comes from `backend/.env` — the same file the Python server
reads, with the same variable names. Nothing new was added.

## Layout

Module-for-module with the Python, so a change on one side is easy to mirror on
the other while both exist.

| Python | TypeScript |
|---|---|
| `app.py` | `src/app.ts` + `src/index.ts` |
| `config.py` | `src/config.ts` |
| `llm.py` | `src/llm.ts` |
| `json_utils.py` | `src/jsonUtils.ts` |
| `rate_limit.py` | `src/rateLimit.ts` |
| `data/*.py` | `src/data/*.ts` |
| `ingestion/*.py` | `src/ingestion/*.ts` |
| `routes/*.py` | `src/routes/*.ts` |
| `routes/itinerary.py` | **removed** — replaced by `src/routeGeneration/` |
| `test_poi_rules.py` | `src/testPoiRules.ts` |
| `backfill_photos.py`, `backfill_descriptions.py`, `translate_curated.py` | `src/scripts/*.ts` |
| — | `src/http.ts`, `src/async.ts`, `src/text.ts`, `src/supabase.ts`, `src/types.ts` |

The five files with no Python counterpart are the shims: `requests`,
`concurrent.futures`, Python's Unicode-aware string methods, supabase-py's
raise-on-error behaviour, and the shared data shapes.

## Endpoints

Everything except route generation is unchanged in path, method, request body
and response body from the Flask server:

```
GET  /api/health
POST /api/chat
POST /api/tasks/generate
POST /api/poi/ingest
POST /api/models/generate
POST /api/auth/delete-account
```

Route generation was replaced wholesale by the Route Generation module — see
[`src/routeGeneration/README.md`](src/routeGeneration/README.md). The old
`/api/itinerary*` endpoints are gone:

```
GET  /api/cities                        list + rollout status
GET  /api/categories                    themes and categories
POST /api/routes                        generate (synchronous)
GET  /api/routes/:routeId
POST /api/routes/:routeId/refine        NOT IN SPEC — see the module README
POST /api/routes/:routeId/progress      start a walk
GET  /api/progress/:progressId
POST /api/progress/:progressId/checkpoint
```

**Nothing below Layer 1 is implemented.** `ROUTE_GENERATION_MODE` defaults to
`fixture`, which serves a placeholder Algiers route so the app is buildable;
`real` calls the orchestrator, which throws `501 not_implemented` naming the
first missing component.

## What is deliberately not here

**`scripts/ingest_geofabrik.py` stays in Python.** It is the only consumer of
`osmium`, a binding to a C++ OSM PBF parser with no maintained Node equivalent.
It is a 139-line offline batch script that talks to Supabase and sits on no
request path, so leaving it where it is costs nothing.

`scratch/` is not ported either; those are throwaway probes, not server code.

## Differences worth knowing

Behavioural parity is verified by [`parity/`](parity/README.md) — a differential
harness that runs both implementations over the same corpus and diffs the
results (currently identical across all 16 sections). What follows is the list
of places where the two languages genuinely required a decision.

**Unicode.** The single largest risk, and the reason `src/text.ts` exists.
Python's `str.isalnum()` is `\p{L}` ∪ `\p{N}`, its `\w` and `\d` match Arabic,
`str.capitalize()` lowercases everything after the first character, and
`str.title()` treats digits as word boundaries. JavaScript agrees with none of
that by default. Every one of these is used by the photo-matching and dedup
rules, where a mismatch degrades results silently rather than raising. All are
pinned in both `npm test` and the parity harness.

**Concurrency.** Every `ThreadPoolExecutor` in the Python wrapped HTTP I/O, so
they became promises plus a semaphore (`src/async.ts`). Three consequences:
the JWT cache and the Overpass bbox cache no longer need locks; the
`PHOTO_WAIT_S` deadline is a `Promise.race` rather than `future.result(timeout)`;
and the limiter replaces the pools outright. (The fire-and-forget generation
thread went with the old itinerary route — generation is synchronous now.)

**Overpass hedging** gained one thing the Python could not do: abandoned mirror
requests are actually cancelled via `AbortController`, where
`pool.shutdown(wait=False)` could only stop waiting for them. That matters
against a service with a documented two-concurrent-query limit.

**supabase-js vs supabase-py.** Two differences, both handled in
`src/supabase.ts`: JS returns `{data, error}` where Python raises (`unwrap()`
restores the raising behaviour so the `try/except` structure ports unchanged),
and JS returns no rows from `insert()`/`upsert()` unless `.select()` is chained
— every call site that reads back an id does.

**Gemini SDK.** The Python called `client.interactions.create(...,
generation_config={'thinking_level': ...})`. The JS SDK's equivalent is
`models.generateContent` with `config.thinkingConfig.thinkingLevel`, and
whether that field is accepted varies by SDK version. `src/llm.ts` sends it,
and on an unknown-field error disables it for the rest of the process rather
than retrying forever or losing the provider. `chat()`'s Groq fallback is
unchanged either way.

**Rounding.** Python rounds halves to even; JavaScript rounds them away from
zero. This can differ in the last decimal of a displayed `distance_km` or a
`pageviews` breakdown entry. Both are cosmetic, and the parity harness
confirms no case in the corpus is affected.

**Express.** Handlers are wrapped in `asyncHandler` because Express 4 hangs a
request whose handler rejects instead of forwarding to the error middleware —
a hazard Flask did not have, since its handlers are synchronous. A malformed
JSON body answers 400 rather than throwing, matching
`request.get_json(silent=True) or {}`.

## Next step for the types

`src/supabase.ts` takes row types as caller-supplied generics rather than
inferring them, because there is no generated `Database` type — without one,
supabase-js widens any `select()` carrying an embedded relation to
`GenericStringError[]`. Running `supabase gen types typescript` and passing the
result to `createClient<Database>` would make those annotations checked instead
of asserted. It is the one place in this port where a type is a claim rather
than a proof.
