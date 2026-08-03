# Backend Handoff — Current State & Remaining Work

This is a status snapshot for an agent picking up backend work on this
project, written at a point where a working Flask server, a live Supabase
project, and a tested POI ingestion pipeline already exist. The numbered
docs (`01` through `12`) and `README.md` in this folder are the *design*
documents — read them for the reasoning behind any decision. This document
is the *current-state* snapshot — read it first, to avoid re-deriving
things that are already built, and to avoid assuming things are built that
aren't. Each numbered doc also carries its own `> **Status:**` note near the
top; those are authoritative for that specific doc's area. This document's
job is to give you the fast, cross-cutting picture before you dive into any
one of them.

**If anything here conflicts with a doc's own status note, trust the doc's
status note — it was updated at the same time as the code it describes, and
this file could theoretically drift after future sessions.** Update this
file's relevant section (and the doc's own status note) whenever you finish
a piece of work, the same way prior sessions did.

---

## Required first step: audit for manual tasks before writing code

**Before implementing anything, produce a list of every manual task the
work will require** — API keys, dashboard toggles, third-party account
setup, App Store / Play Store configuration, anything that needs a human
with credentials this agent doesn't have. Two categories:

1. **Already known** — listed in "Manual tasks already completed" and
   "Manual tasks known but not yet done" below. Confirm these are still
   accurate (an env var can be unset again, a dashboard setting can drift)
   rather than assuming the list is current.
2. **New, specific to what you're about to build** — e.g., if you implement
   doc 07 (securing the 3D endpoint), the user will need to create a Modal
   proxy-auth token in the Modal dashboard and set a spend limit; if you
   implement doc 01 (auth), they'll need to enable anonymous sign-in in the
   Supabase dashboard and, if adding OAuth, register the app with each
   provider. **Identify these before starting, not after** — surface them
   as a list at the start of your response, the same way manual-config
   needs were flagged throughout this project's history so far. Don't
   silently write code that depends on a credential nobody's been told to
   provide.

Never fetch or print a secret key's value in conversation. Where you need
one that isn't set, name exactly what it is, where to find it, and why —
the pattern already established in `backend/.env.example` and in
`config.py`'s `require_llm_key()` / `require_service_role_key()` helpers.

---

## Orientation

- **Backend server**: `backend/server/` — a Flask app, Python. This is
  where all work described below lives. `backend/hunyuan2.1/` is a
  separate, untouched Modal service (see doc 06/07).
- **Database**: Supabase project `csrmogytbbjkbjmgedgx`, accessed via the
  Supabase MCP server (already configured and authenticated — confirm
  `claude mcp list` or equivalent shows it before assuming it's available)
  and via `supabase-py` from Flask. Schema is committed at
  `supabase/migrations/*.sql` (six files so far) and `supabase/seed.sql`.
  **Migrations were applied via MCP's `apply_migration`, not the Supabase
  CLI** — there's no local Postgres, no `supabase start`. Keep using MCP
  tools (`apply_migration`, `execute_sql`, `get_advisors`) the same way,
  and keep writing the resulting SQL into `supabase/migrations/` afterward
  so the committed files stay truthful — `list_migrations` gives you the
  authoritative applied list to check against.
- **Flutter app**: `lib/` — **entirely untouched by any of this work.**
  Every endpoint described below exists and works, but nothing in the app
  calls any of them yet. `AppBloc` still runs on the original static data
  and canned responses.
- **Running the server**: `cd backend/server && venv/Scripts/python.exe
  app.py` (Windows venv already set up with dependencies installed —
  `requirements.txt` is current). Serves on `:8000`. Stop with a process
  kill, not Ctrl-C, if running it backgrounded during testing.
- **This project's testing bar**: every piece of backend work completed so
  far was verified against real external services (real Groq calls, real
  Overpass/Wikidata/Wikipedia/Commons traffic, real Supabase queries) —
  never mocked, never assumed from reading the code. Two real, non-obvious
  bugs were only found this way (see "Known issues found and fixed"
  below) — code review alone did not catch them. Hold new work to the same
  bar: run it for real, inspect the actual persisted/returned data, don't
  stop at "it didn't throw."

---

## What's implemented

### Flask server (`backend/server/`)

| File | Role |
| --- | --- |
| `app.py` | Creates the app, registers blueprints |
| `config.py` | Reads `backend/.env`; `require_llm_key()` / `require_service_role_key()` raise a clear error naming what's missing and where to find it |
| `llm.py` | Groq client wrapper. **Note**: `LLM_MODEL` (`qwen/qwen3.6-27b`) is a reasoning model that burns its token budget on a hidden `<think>` trace unless `reasoning_effort="none"` is passed — this is set unconditionally in every call. If the model is ever changed, re-verify this still applies; it was a real bug the first time this was wired up |
| `json_utils.py` | Defensive JSON extraction from LLM text output (handles fenced blocks, stray prose) |
| `data/curated_locations.py` | The 8 hand-verified locations. Originally the only data source; now purely the **hardcoded fallback** — degrades to this on any Supabase failure |
| `data/geo.py` | `haversine_km()` — shared, source-independent |
| `data/supabase_client.py` | Anon-key client. Every *read* path uses this |
| `data/locations_repo.py` | `locations_within_radius()`, `get_location()` — Supabase-first, catches any exception and falls back to `curated_locations`, logs via `logger.exception` |
| `routes/health.py` | `GET /api/health` |
| `routes/itinerary.py` | `POST /api/itinerary` — the three-stage funnel: `nearby_locations` RPC → Groq selection (skipped if no `prompt`) → nearest-neighbour ordering |
| `routes/chat.py` | `POST /api/chat` — grounded place chat, refuses to invent opening hours/prices |
| `routes/tasks.py` | `POST /api/tasks/generate` — generates and validates a photo/video/scan/mascot task per location |
| `routes/poi.py` | `POST /api/poi/ingest` — manual trigger for ingestion, requires `SUPABASE_SERVICE_ROLE_KEY`, returns 503 with a clear message if unset |

### Ingestion pipeline (`backend/server/ingestion/`)

Implements doc 12's three-stage funnel (fetch → score → dedupe/persist) for
real. All of it has been run against live external APIs, not mocked.

| File | Role |
| --- | --- |
| `supabase_admin.py` | The **only** place holding `SUPABASE_SERVICE_ROLE_KEY`. Separate client from the anon one — never merge these |
| `tiling.py` | Grid-based tile covering (`TILE_SIZE_DEG = 0.045` ≈ 5km, `MAX_TILES_PER_INGEST = 3` — cut down from 9 after empirically hitting Overpass's rate limit) |
| `overpass.py` | `fetch_pois()`. **Raises `OverpassError` on failure** — this used to silently return `[]`, which caused a real cache-poisoning bug (see below); don't revert that |
| `wikidata.py` | `fetch_wikidata_items()` (per-tile SPARQL "around" query — heritage, image, article, sitelinks), `match_nearest()` (proximity fallback when no explicit `wikidata=` OSM tag) |
| `wikipedia.py` | `fetch_summary()` (extract + thumbnail + original image URL), `fetch_pageviews_30d()` (daily granularity summed over 30 days — the monthly-endpoint version 400'd in live testing, don't revert to it without re-verifying the date format) |
| `commons.py` | `resolve_commons_file()` — license/attribution lookup; returns `None` if either is missing rather than a photo with no credit |
| `photos.py` | `resolve_photo()` — Wikipedia-thumbnail-first, then Wikidata P18, then OSM `wikimedia_commons` tag. Its docstring documents a real empirical test of search-engine-based photo discovery and why it was rejected (a "safe-looking" Commons-restricted search result turned out to depict a building in Portugal, not Algeria) — **don't re-attempt that approach without reading that writeup first** |
| `scoring.py` | `compute_score()` — the full weight table from doc 12, plus a generic-name regex penalty not in the original spec |
| `ingest.py` | `ensure_tiles_ingested()` / `_ingest_one_tile()` — the orchestrator. Dedup is **two-tier**: exact Wikidata QID match first (added after a live bug — see below), `find_location_match` RPC (proximity + trigram) second |

### Supabase (project `csrmogytbbjkbjmgedgx`)

Schema is catalogue-only — no user accounts, trips, or artifacts exist yet
(that's doc 02's unimplemented half, see below).

- **Tables**: `regions`, `region_translations`, `locations` (with doc 12's
  scoring/provenance columns), `location_translations`, `location_tasks`,
  `location_task_translations`, `poi_tiles`, `poi_source_links`.
- **RPCs**: `nearby_locations` (the radius+score query, `anon`/`authenticated`
  can call it), `find_location_match`, `upsert_ingested_location`,
  `upsert_poi_tile` (all three **service_role only** — explicitly revoked
  from `anon`/`authenticated`, not just `public`; see "Known issues" below
  for why that distinction mattered).
- **RLS**: enabled on every table. Catalogue tables are world-readable,
  write-only via `service_role`. Ingestion tables (`poi_tiles`,
  `poi_source_links`) have zero policies for `anon`/`authenticated` —
  intentional default-deny.
- **Data currently present**: the 8 curated (`is_curated = true`) locations,
  plus 15 real locations ingested during live testing around central
  Constantine, plus 3 cached `poi_tiles` covering that same area. This is
  real data from a real test run, not synthetic — treat it as a small,
  genuine sample of what ingestion produces, and feel free to ingest more
  areas the same way (`POST /api/poi/ingest`) to get more to work with.
- **Migrations**: `supabase/migrations/20260801104713_catalogue_schema.sql`
  through `20260801110806_poi_ingestion_functions_lockdown.sql` (six files),
  `supabase/seed.sql` for the curated 8.

### Known issues found and fixed during live testing

Worth reading before touching this code, so the same mistakes aren't
reintroduced:

1. **RLS default-grant trap.** `revoke execute ... from public` on the
   three service-role RPCs did *not* actually block `anon`/`authenticated`
   — Supabase grants those roles direct `EXECUTE` via `ALTER DEFAULT
   PRIVILEGES`, independent of the `PUBLIC` pseudo-role grant. Only caught
   by calling the RPC with the real anon key and checking for a permission
   error, not by reading the SQL. **Generalize this**: whenever a new
   Postgres function needs to be restricted, verify with a real anon-key
   call, don't trust `revoke ... from public` alone.
2. **Dedup miss.** The curated `ahmedbey` seed coordinate is 432m from
   OSM's actual mapped point for the same building, and the OSM name
   doesn't trigram-match the curated name — both outside
   `find_location_match`'s thresholds. Both records agreed on the same
   Wikidata QID. Fixed by adding an exact-QID check as the first dedup
   tier. **If you add more curated locations by hand, their `wikidata_qid`
   should be populated at seed time if it's known**, to give ingestion the
   strongest possible signal from the start.
3. **Cache poisoning on transient failure.** A real Overpass 504 resulted
   in a tile being cached `fetch_status='ok', poi_count=0` for the normal
   60-day TTL — indistinguishable from "genuinely nothing here." Fixed by
   having `overpass.fetch_pois` raise instead of swallowing the failure.
   **Any new external-API call added to the ingestion path should raise on
   failure, not return an empty/default value** — let the existing
   tile-level exception handling in `ensure_tiles_ingested` do its job.

### Manual tasks already completed

These environment variables are set in `backend/.env` and confirmed
working:

- `GROQ_API_KEY`, `LLM_MODEL` — LLM provider
- `SUPABASE_URL`, `SUPABASE_ANON_KEY` — read path
- `SUPABASE_SERVICE_ROLE_KEY` — ingestion write path
- `OVERPASS_CONTACT` — real contact info in the Overpass/Wikidata/Wikipedia
  User-Agent (fair-use compliance)

The Supabase MCP server is configured and authenticated for this project.

---

## What's NOT implemented

Ordered roughly by what's likely to matter most next, not by doc number.
Each doc's own status note has more detail than this summary.

### 1. (Resolved) 3D generation endpoint authentication

This has been fully addressed. The endpoint now runs behind the Flask backend which handles JWT verification, rate limiting, and quota deduction before securely proxying the request to Modal. The Modal worker itself verifies the file extension, ensures pixel bounds, runs NSFW image detection, and pushes directly to Supabase storage.

### 2. Flutter app integration: fully implemented

The Flutter app (`lib/`) is now fully connected to the Flask backend and Supabase:
- `SupabaseService` initializes `supabase_flutter` with platform keychains (`flutter_secure_storage`) for session persistence.
- `AuthBloc` automatically signs in users anonymously on first launch (`signInAnonymously()`).
- `ApiClient` attaches the user's Supabase JWT on **every** request.
- `LocationRepository` calls `POST /api/itinerary` for route generation (with LLM selection, ordering & reasons).
- `ChatRepository` calls `POST /api/chat` for grounded place chat and `POST /api/itinerary/modify` for AI route edits.
- `TaskRepository` calls `POST /api/tasks/generate` for real LLM challenge generation.
- Full 3D generation flow: on-device object detection (`google_mlkit_image_labeling`), JPEG compression & EXIF stripping (`flutter_image_compress`), optimistic folder insert, upload to Supabase `captures` bucket, Modal job submission via `POST /api/models/generate`, Realtime job monitoring, GLB downloading/caching (`MediaCache`), and native 3D viewing (`flutter_3d_controller`).

### 3. Auth & accounts — [doc 01](01-auth-and-accounts.md): fully implemented

Supabase Auth triggers and cron jobs (`purge_anonymous_users`) are live in the database. Flask endpoint for account deletion exists (`POST /api/auth/delete-account`).
`AuthBloc` is live on the frontend, handling anonymous sign-in, session restoration, and sign-out cleanup. Anonymous sign-in is enabled in the Supabase dashboard.

### 4. The rest of the cloud schema — [doc 02](02-cloud-database-schema.md)

Catalogue and user-scoped schema are fully applied via 13 SQL migrations (`profiles`, `trips`, `trip_stops`, `saved_locations`, `artifacts`, `model_jobs`, `chat_messages`, `swipe_decisions`, and their RLS/triggers).

### 5. Local database, sync, storage — [doc 03](03-local-database-schema.md), [04](04-sync-and-caching.md), [05](05-storage-and-media.md): storage & media implemented

Supabase Storage buckets (`captures`, `models`, `thumbnails`, `catalogue`) are fully created via SQL migrations with RLS policies in place, alongside maintenance cron jobs for purging orphan objects. `MediaCache` on Flutter caches downloaded `.glb` models on disk.

### 6. 3D generation pipeline — [doc 06](06-3d-generation-pipeline.md): fully implemented (backend & Flutter)

The Modal API endpoint (`backend/hunyuan2.1/api.py`) handles asynchronous jobs via `Generator.generate.spawn`, includes validation and caching, and pushes the resulting `.glb` to Supabase Storage. Flutter client integration is complete with on-device object detection, upload, Realtime tracking, and 3D GLB viewer.

### 7. LLM features — [doc 08](08-llm-and-ai-features.md): fully implemented (backend & rate limiting)

All four features are now live and rate-limited via Supabase `check_rate_limit` RPC:
- Itinerary generation (`POST /api/itinerary`) — Gemini-primary, Groq-fallback (30 reqs/hr rate limit)
- Place chat (`POST /api/chat`) — grounded, refuses to invent opening hours (60 reqs/hr rate limit)
- Task generation (`POST /api/tasks/generate`) — validated against task_type enum (50 reqs/hr rate limit)
- "Modify my route" (`POST /api/itinerary/modify`) — LLM route adjustment (30 reqs/hr rate limit)
- All LLM endpoints require a valid Supabase JWT Bearer token and enforce per-user rate limiting via `rate_limit.py`.

### 8. i18n and theming — [doc 09](09-internationalization.md), [10](10-theming-light-dark.md): not started

`locale='en'` is hardcoded throughout the new backend (the schema supports
more locales; nothing populates or requests them). No ARB files, no dark
mode.

### 9. Ingestion gaps — [doc 12](12-poi-sources-and-ingestion.md)

The pipeline itself works (see above), but: no `fr`/`ar` translation of
ingested content, no LLM rewrite pass on Wikipedia extracts for tone, no
`poi_merge_overrides` table for manually correcting a bad dedup match, no
pre-warming/scheduled refresh (everything is on-demand and synchronous —
see doc 12's "Ingestion Edge Function" status note on why), and **no rate
limit on `POST /api/poi/ingest` itself** ([doc 11](11-security-checklist.md)
open issue #9) — low risk today since the endpoint isn't linked anywhere,
but real if it ever becomes reachable from outside a developer's own
testing.

---

## Suggested approach

1. Do the manual-task audit described at the top, for whatever you're
   about to work on specifically — not the whole list generically.
2. Pick one area. Doc 07 (3D endpoint auth) is the standing top priority
   if nothing else takes precedence, per every security review so far.
   Wiring the Flutter app to the existing endpoints (#2 above) is the
   biggest unlock for making the last two sessions' work actually visible.
3. Read that area's numbered doc in full, including its status note.
4. Implement, then **verify against the real thing** — real API calls,
   real Supabase queries to confirm what was actually persisted, not just
   a 200 response. This project's history so far has two examples of bugs
   that only live testing caught; code review and unit-style checks alone
   would have missed both.
5. Update that doc's status note and this file's relevant section to match
   what's now true, the same way every prior session did.
