# AI Tour — Backend Implementation Plan

These docs describe how to take the app from its original state — a single
in-memory `AppBloc` seeded from `lib/models/location_data.dart`, plus an
unauthenticated GPU endpoint in `backend/hunyuan2.1/` — to an account-based,
offline-capable, multilingual product with a secured 3D generation pipeline.

**Implementation has started.** A Flask server at `backend/server/` and a
Supabase project (schema committed under `supabase/migrations/`) now back
three real endpoints — itinerary generation, place chat, and task
generation — plus a live POI ingestion pipeline. Each doc below carries a
status line stating what's actually built versus still planned; don't infer
implementation status from the prose alone, since these documents were
written before any code existed and mostly still describe intent rather
than what's live. The Flutter app itself is untouched so far — everything
built to date is server-side.

**Picking up this work?** Read [HANDOFF.md](HANDOFF.md) first — a
current-state snapshot (what's implemented, what's not, known issues found
during live testing) written specifically for an agent starting a new
session, rather than the numbered docs' original design intent.

---

## Where the app is today

Understanding the starting point matters, because it determines how invasive
each piece of work is.

| Area | Current state | Consequence |
| --- | --- | --- |
| State | One `AppBloc`, all state in memory, lost on kill | Every persisted field is new work, but the event API is already the right seam |
| Data | Static `allLocations` list of 8 hardcoded `Location`s | Becomes a **cache of live POI data** from a maps API, scored and deduped. The 8 stay as curated fallbacks |
| Auth | None | Entirely new |
| Persistence | None. AR captures write PNGs to the app documents dir and are referenced by absolute path | Paths break across reinstalls; needs a real local DB + storage abstraction |
| Radius filter | `radiusKm` exists in state and UI but the query in `app_bloc.dart` filters on region only | Radius must become a real geospatial predicate |
| 3D generation | Modal endpoint exists, works, is completely public and synchronous | Needs auth, async job model, and quota |
| Artifact viewer | A photo-textured cube (`lib/widgets/cube3d.dart`) — not a real 3D model renderer | Displaying generated `.glb` needs a real viewer |
| i18n | ~20 hardcoded UI strings in screens plus all seed content in English | Needs ARB extraction + a content translation strategy |
| Theme | 224 references to `AppTheme.` static consts across 34 files | Dark mode is a refactor, not a toggle |
| Route generation | **Implemented server-side.** `POST /api/itinerary` runs the full three-stage funnel — Supabase `nearby_locations` → LLM selection (Groq) → nearest-neighbour ordering. The Flutter app doesn't call it yet | Wire `GenerateRouteEvent` to this endpoint |
| AI features | **Implemented server-side.** `POST /api/chat` and `POST /api/tasks/generate` are live against Groq, grounded and validated per doc 08. Not yet called from Flutter | Wire `AskQuestionEvent`/`RegenerateTaskEvent` to these endpoints |
| POI data | Was 8 hardcoded rows | **Now Supabase-backed and live-ingestible.** Same 8 rows seeded as `is_curated`, plus a working Overpass/Wikidata/Wikipedia/Commons ingestion pipeline (`backend/server/ingestion/`, triggered via `POST /api/poi/ingest`) that scores and dedupes real POIs into the same table |

## Target architecture

```
┌───────────────────────────────────────────────────────────┐
│  Flutter app                                              │
│                                                           │
│  UI  ──►  AppBloc  ──►  Repositories  ──►  Local DB       │
│                              │             (Drift/SQLite) │
│                              │                  ▲         │
│                              ▼                  │         │
│                         Sync engine ────────────┘         │
└──────────────────────────────┬────────────────────────────┘
                               │ HTTPS, Supabase JWT
                               ▼
┌───────────────────────────────────────────────────────────┐
│  Supabase                                                 │
│    Auth  ·  Postgres + PostGIS  ·  Storage  ·  Realtime   │
│    Edge Functions (the ONLY holder of third-party keys)   │
└───┬───────────────────────┬──────────────────────┬────────┘
    │ proxy auth            │ server-side key      │ server-side
    ▼                       ▼                      ▼
┌─────────────────┐  ┌───────────────┐  ┌────────────────────┐
│ Modal           │  │ LLM provider  │  │ Maps / POI APIs    │
│ Hunyuan3D on L4 │  │ Gemini, Groq  │  │ Overpass, Wikidata │
└─────────────────┘  └───────────────┘  └────────────────────┘
```

### Route generation is a funnel, not a prompt

```
1. FETCH   Maps API → tourism POIs near the user       (cached by tile)
2. SCORE   Deterministic ranking — is this worth visiting at all?
3. SELECT  LLM picks and orders from the top candidates, per the user's prompt
```

The model never invents a place; it only chooses from rows a maps provider
vouched for. Stage 2 is where the product lives — raw POI feeds return the
Casbah alongside gift shops and car parks, and filtering that cheaply before
the model sees it is both a quality and a cost decision.
Full detail in [12](12-poi-sources-and-ingestion.md).

### The one rule that drives most of the design

**The app never talks to a paid or GPU-backed third party directly.** Every
such call goes through a trusted server that authenticates the request,
checks quota, and holds the API key. This single rule is why the 3D
endpoint, the LLM calls, and any future paid API all share the same shape.

An API key shipped inside an APK is a public key. Anyone can `unzip` the
bundle, pull the string out, and spend your GPU credits.

**Architecture update:** the docs below were written assuming that trusted
server would be Supabase Edge Functions (Deno/TypeScript). Implementation
started with a **Flask server** at `backend/server/` instead — a deliberate
choice to keep the whole backend in one language, alongside the existing
Python Modal service in `backend/hunyuan2.1/`. The principle is unchanged
(one trusted server holds the keys, the app never does); only the runtime
differs. Flask currently holds the Groq key and, for the ingestion pipeline
specifically, the Supabase `service_role` key
(`backend/server/ingestion/supabase_admin.py`) — kept deliberately separate
from the `anon`-key client every read path uses
(`backend/server/data/supabase_client.py`). Wherever a doc below says "Edge
Function," read "Flask route" — the security properties described still
apply, just implemented in a different runtime. Doc 07 (securing the 3D
endpoint) still describes an Edge Function proxy in front of Modal; that
work hasn't started, and when it does it should likely become a Flask route
too, for the same consistency reason.

## Document index

Read [12](12-poi-sources-and-ingestion.md) early — it defines where location
data comes from, so it logically precedes 02 and 08. It's numbered last only
to keep existing cross-links stable.

| # | Document | Covers | Status |
| --- | --- | --- | --- |
| 12 | [POI sources & ingestion](12-poi-sources-and-ingestion.md) | Maps API comparison, tile cache, dedupe, interestingness scoring | **Substantially implemented** |
| 01 | [Auth & accounts](01-auth-and-accounts.md) | Anonymous-first sign-in, upgrade to email/OAuth, session handling, account deletion | Not started |
| 02 | [Cloud database schema](02-cloud-database-schema.md) | Full Postgres schema, PostGIS radius queries, RLS policies, migrations | **Partially implemented** — catalogue only |
| 03 | [Local database schema](03-local-database-schema.md) | Drift/SQLite mirror, what's cached vs. authoritative, encryption | Not started |
| 04 | [Sync & caching](04-sync-and-caching.md) | Offline outbox, conflict resolution, cache tiers and TTLs | Not started |
| 05 | [Storage & media](05-storage-and-media.md) | Buckets, upload paths, signed URLs, thumbnails, local file lifecycle | Not started |
| 06 | [3D generation pipeline](06-3d-generation-pipeline.md) | Camera → job → `.glb` → viewer, end to end, plus fixes to the Modal function | Not started |
| 07 | [Securing the 3D endpoint](07-securing-the-3d-endpoint.md) | Concrete hardening of `backend/hunyuan2.1/api.py` | **Not started — highest-priority open item** |
| 08 | [LLM & AI features](08-llm-and-ai-features.md) | Free models for itinerary generation, chat, translation, moderation, embeddings | **Partially implemented** — 3 of 5 features |
| 09 | [Internationalization](09-internationalization.md) | ARB setup, RTL for Arabic, translating user-generated and seed content | Not started |
| 10 | [Theming — light & dark](10-theming-light-dark.md) | Migrating 224 static const references to a themeable system | Not started |
| 11 | [Security checklist](11-security-checklist.md) | Consolidated review, threat model, pre-launch gate | Partially addressed — new work only |
| 12 | [POI sources & ingestion](12-poi-sources-and-ingestion.md) | *(listed above — read first)* | |

"Not started" means no Flutter or backend code exists for that doc yet — it's still exactly a plan. Where a doc is marked implemented, its own top-of-file status note gives specifics; don't assume full coverage from the table alone.

## Suggested build order

Each phase leaves the app in a shippable state.

**Phase 1 — foundations (no user-visible change)**
Repository layer between `AppBloc` and data · Drift local DB · models get
JSON serialization · seed `allLocations` into SQLite instead of a Dart list.
Ship it: the app behaves identically but now survives being killed.
*Status: not started — this is Flutter-side work; everything built so far
is the backend those repositories will eventually call.*

**Phase 2 — accounts and cloud**
Supabase project · schema + RLS · anonymous auth on first launch · sync engine
for saved locations, trips, points. Ship it: progress follows the user.
*Status: the Supabase project and catalogue schema/RLS exist
(`supabase/migrations/`); auth, trips, saved locations, and the sync engine
do not.*

**Phase 3 — real POI data**
Ingestion Edge Function · tile cache · dedupe · interestingness scoring ·
Wikidata/Wikipedia/Commons enrichment. Ship it: the map covers real geography
instead of 8 hardcoded points, and the radius slider works.
*Status: implemented, as a Flask route rather than an Edge Function — see
`backend/server/ingestion/` and doc 12's status note. Verified end-to-end
for real, including persistence: a live `POST /api/poi/ingest` call
populated Supabase with 15 new locations alongside the 8 curated ones, and
`/api/itinerary` correctly served a mix of both afterward. Two real bugs
surfaced by that run — a dedup miss and a cache-poisoning failure mode —
were fixed and re-verified; see doc 12's status note for both. Not yet
called from Flutter, and not yet wired to auto-trigger from a user's radius
query (deliberately — see routes/poi.py's docstring on why it's a separate,
explicitly-triggered endpoint rather than an inline step).*

**Phase 4 — LLM selection**
The model layer on top of phase 3's candidates, plus the chat surfaces. This
is deliberately *after* ingestion: without scored candidates there's nothing
worth prompting a model about.
*Status: implemented — `POST /api/itinerary`, `/api/chat`,
`/api/tasks/generate` in `backend/server/routes/`, against Groq. Not yet
called from Flutter.*

**Phase 5 — the 3D feature**
Harden the Modal endpoint · Edge Function proxy · job table · camera flow ·
real `.glb` viewer replacing the photo cube.
*Status: not started. The Modal endpoint is still unauthenticated — see
doc 07's status note for why this is the single highest-priority gap left.*

**Phase 6 — polish**
i18n · dark mode.
*Status: not started.*

Phases 1–2 are unglamorous but everything else sits on them. Doing the 3D
feature first means building the job queue twice, and doing phase 4 before
phase 3 means prompting a model with hardcoded data you're about to delete.

## Immediate housekeeping

`backend/hunyuan2.1/venv/` is untracked and contains ~13,600 files. Add this
to `.gitignore` before the next `git add`:

```gitignore
# Python
backend/**/venv/
backend/**/__pycache__/
backend/**/*.pyc

# Generated 3D output — regenerable, and large
backend/**/results/
backend/**/*.glb
```

`backend/hunyuan2.1/result.glb` and `results/*.glb` are build output; keep one
small fixture for tests if you need it, ignore the rest.

## Cost expectations

The plan is built to stay inside free tiers wherever it can, with one
exception you should budget for deliberately.

- **Supabase free tier** — 500 MB database, 1 GB storage, 2 GB egress,
  50,000 monthly active users. Comfortable for development and a small
  launch. Storage is the first thing you'll outgrow: see
  [05](05-storage-and-media.md) for the retention policy that delays that.
- **Modal** — offers free monthly compute credit for new accounts; past that
  it's per-second GPU billing. An L4 running a Hunyuan3D 2.1 shape+paint pass
  is the real cost centre in this app. [06](06-3d-generation-pipeline.md) and
  [07](07-securing-the-3d-endpoint.md) treat per-user quota as a correctness
  requirement, not a nice-to-have.
- **LLM inference** — genuinely free at this app's scale via the providers in
  [08](08-llm-and-ai-features.md).
- **Maps & POI data** — the recommended stack (Overpass/OSM, Wikidata,
  Wikipedia, Wikimedia Commons) is free with no key and no billing card. What
  it costs instead is compliance: attribution, a real `User-Agent`, and
  fair-use rate limiting. CartoDB basemaps and Nominatim are already in use
  under the same terms. See [12](12-poi-sources-and-ingestion.md) and
  [11](11-security-checklist.md).

## Conventions used across these documents

- SQL is Postgres 15+ as shipped by Supabase.
- Dart snippets are illustrative sketches, not final code.
- **Must** marks something load-bearing for security or correctness.
  **Should** marks a strong recommendation. Anything else is a suggestion.
- Verify current free-tier limits and model availability against provider
  docs before committing — those change faster than documentation does.
