# Backend Handoff — Current State & Remaining Work

A status snapshot for an agent picking up backend work. The numbered docs
(`01`–`13`) and `README.md` are the *design* documents — read them for the
reasoning behind a decision. This is the *current-state* snapshot: read it
first, to avoid re-deriving what's already built and to avoid assuming things
are built that aren't.

Each numbered doc carries its own `> **Status:**` note near the top. **Those
notes are authoritative for their area, and the prose beneath them frequently
is not** — several docs describe designs the implementation deliberately
walked away from. This file's job is the fast cross-cutting picture.

Update this file's relevant section (and the doc's own status note) whenever
you finish a piece of work, the way prior sessions did.

---

## Required first step: audit for manual tasks before writing code

**Before implementing anything, list every manual task the work will require**
— API keys, dashboard toggles, third-party account setup, store
configuration, anything needing a human with credentials this agent doesn't
have. Two categories:

1. **Already known** — see "Manual tasks" below. Confirm they're still
   accurate (an env var can be unset, a dashboard setting can drift) rather
   than assuming the list is current.
2. **New, specific to what you're about to build.** Identify these *before*
   starting and surface them at the top of your response. Don't silently write
   code that depends on a credential nobody's been told to provide.

Never fetch or print a secret's value. Where one is missing, name what it is,
where to find it, and why — the pattern in `backend/.env.example` and
`config.py`'s `require_llm_key()` / `require_service_role_key()` /
`require_modal_keys()` helpers.

---

## Orientation

- **Backend server**: `backend/server/` — Flask, Python. Run with
  `cd backend/server && venv/Scripts/python.exe app.py` (Windows venv already
  set up, `requirements.txt` current). Serves on `:8000`. Kill the process
  rather than Ctrl-C if you backgrounded it.
- **Modal service**: `backend/hunyuan2.1/` — the GPU worker. No longer
  "untouched": it was rewritten into `submit` / `Generator` / `status` and is
  now proxy-authed (docs 06, 07).
- **Database**: Supabase project `csrmogytbbjkbjmgedgx`, via the Supabase MCP
  server and `supabase-py` from Flask. **Migrations are applied via MCP's
  `apply_migration`, not the Supabase CLI** — there's no local Postgres, no
  `supabase start`. Keep using MCP (`apply_migration`, `execute_sql`,
  `get_advisors`) and keep writing the SQL into `supabase/migrations/`
  afterward. `list_migrations` is the authoritative applied list — **it and
  the committed folder currently disagree; see "Known drift" below.**
- **Flutter app**: `lib/` — **fully wired to the backend.** This reverses what
  this file said for most of its life. `AppBloc` calls real endpoints through
  `lib/repositories/`; nothing runs on canned responses any more.
- **This project's testing bar**: every backend change so far was verified
  against real external services (real Groq/Gemini calls, real
  Overpass/Wikidata/Wikipedia/Commons traffic, real Supabase queries) — never
  mocked, never assumed from reading the code. Several non-obvious bugs were
  found *only* this way (see "Bugs found by live testing"). Hold new work to
  the same bar: run it for real, inspect the actual persisted data, don't stop
  at "it didn't throw."

---

## What's implemented

### Flask server (`backend/server/`)

| File | Role |
| --- | --- |
| `app.py` | Creates the app, registers seven blueprints |
| `config.py` | Reads `backend/.env`; `require_*` helpers raise a clear error naming what's missing |
| `llm.py` | **Two providers, either backing the other.** `chat(prefer=)` picks which is tried first — Gemini (`gemini-3-flash-preview`) by default, Groq for latency-critical calls; Groq itself falls back to `llama-3.3-70b-versatile`. `thinking_level` is now a per-call dial (measured: `minimal` 5.5s vs `medium` 16.1s for the *same* itinerary output). Also `embed()` (Gemini, 384-dim) and `extract_intent()` (**unused by any request path**) |
| `rate_limit.py` | `authenticate_and_rate_limit()` — JWT verify + `check_rate_limit` RPC. Caches verified JWTs for 60s (the job-poll loop was re-verifying the same token every second). **Fails open** — see "Known issues" |
| `json_utils.py` | Defensive JSON extraction from LLM output |
| `data/geo.py` | `haversine_km()` and `get_travel_time_matrix()` (public OSRM, 6s timeout, `None` on failure) |
| `data/locations_repo.py` | Catalogue reads, curated fallback on any exception. **Only `/api/chat` and `/api/tasks/generate` still use this** |
| `data/curated_locations.py` | The 8 hand-verified locations, hardcoded fallback |
| `routes/health.py` | `GET /api/health` |
| `routes/itinerary.py` | `POST /api/itinerary` (async job), `GET /api/itinerary/job/<id>`, `GET /api/itinerary/job/latest`, `POST /api/itinerary/modify`, `POST /api/itinerary/accept`. **Read its module docstring** — it records why candidates come from live Overpass rather than the catalogue |
| `routes/chat.py` | `POST /api/chat` — grounded place chat |
| `routes/tasks.py` | `POST /api/tasks/generate` — validated against the task_type enum |
| `routes/models.py` | `POST /api/models/generate` — JWT, rate limit, atomic credit consume with refund at every early return, SHA-256 dedupe, signed URL, Modal proxy handoff |
| `routes/auth.py` | `POST /api/auth/delete-account` — purges the user's storage objects, then the auth user |
| `routes/poi.py` | `POST /api/poi/ingest` — manual ingestion trigger, service-role only |

**The route pipeline, end to end:** client POSTs → `route_jobs` row inserted,
`{job_id}` returned immediately → background thread builds candidates from
live Overpass, ranks them (`interest_score − distance_km × 2`), starts photo
lookups on the top 16 *underneath* the LLM call, asks the model to pick 8 from
the top 30, orders them against an OSRM travel-time matrix concurrently with
the outstanding photo lookups (8s ceiling), writes `result_data` → client
polls `/job/<id>` on a backoff while the thinking screen plays.

Both `/api/itinerary` and `/api/itinerary/modify` build candidates through the
**one** `_build_candidates`. They used to disagree — generate returned
`osm-*` ids, modify validated against uuid-keyed catalogue rows — so every
modify silently replaced the whole route instead of adjusting it. **Don't
split them again.**

### Ingestion pipeline (`backend/server/ingestion/`)

Implements doc 12's fetch → score → dedupe/persist funnel. All of it has run
against live external APIs. **It is no longer in the request path** — see
"Known drift". `overpass.py` is the exception: the route path uses it
directly, and it gained mirror hedging (three mirrors, next started after 5s,
first usable response wins) plus a 10-minute bbox cache to make that viable.

Other modules: `tiling.py`, `wikidata.py`, `wikipedia.py`, `commons.py`,
`photos.py`, `scoring.py`, `ingest.py`, `supabase_admin.py` (the **only**
holder of the service-role key — never merge it with the anon client), plus
two added since: `describe.py` (deterministic + LLM blurbs for POIs Wikipedia
has never heard of — read its docstring, it's the record of how 190 of 203
blurbs came to read "A historic yes.") and `rewrite.py` (LLM blurb rewrite +
fr/ar translation).

`scripts/ingest_geofabrik.py` parses an Algeria OSM PBF offline. It has
evidently never been run against the live project.

### Supabase (`csrmogytbbjkbjmgedgx`)

**14 tables, RLS enabled on all of them:** `regions`, `region_translations`,
`locations`, `location_translations`, `location_tasks`,
`location_task_translations`, `poi_tiles`, `poi_source_links`, `profiles`,
`artifacts`, `model_jobs`, `rate_limit_events`, `saved_locations`,
`route_jobs`.

**Dropped as unused** (migration `20260805101612`): `trips`, `trip_stops`,
`chat_messages`, `swipe_decisions`, the original `saved_locations`,
`artifacts.trip_id`, the `task_state` enum. Rollback script in
`supabase/rollback/`.

**Storage**: `captures`, `models`, `thumbnails`, `catalogue` — all four exist
with size limits and MIME allow-lists. Only `captures` and `models` are used.

**Cron**: `purge-stale-anon` (daily 03:00), `purge-orphan-media` (daily
04:00), `reset-credits` (daily), `reconcile-stuck-jobs` (every 5 min).

**Row counts** (as of this writing): `profiles` 17, `route_jobs` 31,
`artifacts` 12, `model_jobs` 10, `rate_limit_events` 53, `regions` 5.
**Everything catalogue-side is 0** — `locations`, its translations,
`location_tasks`, `poi_tiles`, `poi_source_links`, and `saved_locations`.

### Flutter app (`lib/`)

Fully wired. `SupabaseService` initializes `supabase_flutter` with
`flutter_secure_storage`; `AuthBloc` signs in anonymously on first launch;
`ApiClient` attaches the JWT to every request (and re-signs-in if it finds no
session). `AppBloc` reaches the backend through `lib/repositories/`:
`location_repository` (generate/poll/resume/accept), `chat_repository`
(chat + modify), `task_repository`, `model_repository` (upload + generate),
`saved_locations_repository` (direct-to-Supabase, RLS-scoped).

The 3D flow runs end to end: on-device labelling → compress + EXIF strip →
optimistic folder insert → upload to `captures` → `POST /api/models/generate`
→ Modal → `.glb` to `models` → Realtime → `MediaCache` → `Flutter3DViewer`.

---

## Known drift — read before trusting anything else

### 1. The catalogue is empty and out of the request path

`/api/itinerary` and `/api/itinerary/modify` call Overpass live and never read
`locations`. The catalogue, its embeddings, its fr/ar translations, and the
`describe.py`/`rewrite.py` blurb work all still exist and all currently serve
nothing. Location ids are `osm-{type}-{id}`.

**This is a deliberate change** (a cold city returned only the 8 curated seeds,
which is worse than a slow request — see `routes/itinerary.py`'s docstring).
What is *not* deliberate is leaving it half-finished. Decide: re-seed the
catalogue and give it a job, or retire it and delete what depends on it.

### 2. `/api/chat` and `/api/tasks/generate` 404 on every real stop

Both resolve their subject via `get_location(location_id)` against that empty
catalogue, while the app sends `osm-*` ids. Every call from a generated route
fails; the app catches it and shows fallback copy, so it looks like flakiness
rather than a break. **`ChatRepository.askAboutPlace` already sends
`location_name` and `blurb` in the body and the backend ignores them** —
accepting those is the small fix. Highest-value backend work outstanding.

### 3. Two schema objects exist only in the live database

`route_jobs` (31 rows) and the recreated `saved_locations` have **no committed
migration file**. Conversely `20260801120005_storage_and_auth_cron.sql` and
`20260801120006_fix_stuck_jobs_cron.sql` are committed but absent from the
applied ledger, though their effects are live. **The repo cannot rebuild the
project it documents.** Fix this before anything needs a clean environment.

### 4. Rate limiting fails open

`rate_limit.py` wraps the `check_rate_limit` call in `try/except: pass`. Any
DB hiccup silently grants unlimited access to every LLM and GPU endpoint.
Combined with unlimited free anonymous sign-up, per-user quota is advisory.
Doc 11 issues #10 and #11.

### 5. Built but never called

`llm.extract_intent()`, `routes/itinerary._expand_categories()`, the
`nearby_locations` semantic ranking, `scripts/ingest_geofabrik.py`, the
`thumbnails` and `catalogue` storage buckets. Each was built for the catalogue
design that step 1 walked away from. None is dead code by accident — check doc
13 before deleting any of it.

---

## Bugs found by live testing

Worth reading so they aren't reintroduced. The first three predate the current
architecture but their lessons don't.

1. **RLS default-grant trap.** `revoke execute ... from public` did *not*
   block `anon`/`authenticated` — Supabase grants those roles `EXECUTE`
   directly via `ALTER DEFAULT PRIVILEGES`. Only caught by calling the RPC
   with the real anon key. **Generalize: verify a restriction with a real
   anon-key call, never by reading the SQL.**
2. **Dedup miss.** The curated `ahmedbey` coordinate is 432m from OSM's mapped
   point and the names don't trigram-match — both outside
   `find_location_match`'s thresholds, but both records agreed on the Wikidata
   QID. Fixed with an exact-QID first tier.
3. **Cache poisoning on transient failure.** An Overpass 504 cached a tile as
   `fetch_status='ok', poi_count=0` for the full 60-day TTL —
   indistinguishable from "genuinely nothing here." Fixed by having
   `fetch_pois` raise. **Any new external call on the ingestion path must
   raise, not return an empty default.**
4. **The rate limiter's ledger was world-writable.** `rate_limit_events` had
   RLS off *and* full DML granted to `anon`/`authenticated`: anyone with the
   publishable key could delete their own rows and reset the 20/day GPU
   ceiling. **A limiter's ledger is part of the limiter.** Migration
   `20260805203000`.
5. **Two independent reasons the 3D flow could never complete**, neither
   visible from either side alone: Modal had no `/submit` endpoint (the Flask
   POST 404'd), and `model_jobs` wasn't in the `supabase_realtime`
   publication, so even a finished job never reached the app. Migration
   `20260805201500`, and note the `replica identity full` — without it the
   stream's `.eq('user_id', ...)` filter has nothing to match in UPDATE
   payloads.
6. **Identity vs. equality in list ordering.** `_order_nearest_neighbor` used
   `list.remove()` and `_order_travel_time` used `stops.index()`; both find
   the first *equal* dict, which silently mis-ordered or mis-indexed the OSRM
   matrix whenever two stops compared equal. Both now key on `id()`.

---

## Manual tasks

**Confirmed set and working** in `backend/.env`: `GROQ_API_KEY`, `LLM_MODEL`,
`GEMINI_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`, `OVERPASS_CONTACT`, `MODAL_PROXY_KEY`,
`MODAL_PROXY_SECRET`, `MODAL_SUBMIT_URL`. Anonymous sign-in is enabled in the
Supabase dashboard. The Supabase MCP server is configured and authenticated.

**Not verifiable from this repo — confirm before launch:**

- The **Modal spend limit and function timeout**. Nothing here can prove
  they're set, and they're the last backstop against a runaway container.
- Whether `LLM_MODEL` (`qwen/qwen3.6-27b`) is still the intended Groq model.
  Note it's a reasoning model that burns its budget on a hidden `<think>`
  trace unless `reasoning_effort="none"` is passed — which `llm.py` does
  unconditionally. **If the model changes, re-verify that this still applies.**

---

## Suggested approach

1. Do the manual-task audit for what you're specifically about to work on.
2. Pick one area. If nothing else takes precedence, the ranked list is:
   **(a)** the chat/tasks id-space break (#2 above — user-visible, small fix),
   **(b)** the missing migrations (#3 — blocks any clean rebuild),
   **(c)** fail-open rate limiting (#4 — real money).
3. Read that area's numbered doc **including its status note**, and treat the
   note as authoritative over the prose.
4. Implement, then **verify against the real thing** — real API calls, real
   Supabase queries confirming what was actually persisted, not a 200
   response. Six bugs in this project's history were caught only that way.
5. Update that doc's status note and this file to match what's now true.
