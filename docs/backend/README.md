# AI Tour — Backend Implementation Plan

Planning documents only. No code in this folder is wired into the app yet.

These docs describe how to take the app from its current state — a single
in-memory `AppBloc` seeded from `lib/models/location_data.dart`, plus an
unauthenticated GPU endpoint in `backend/hunyuan2.1/` — to an account-based,
offline-capable, multilingual product with a secured 3D generation pipeline.

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
| Route generation | Region filter over the hardcoded list | Becomes a three-stage funnel: maps API → deterministic scoring → LLM selection |
| AI features | `SendAIChangeEvent` and the detail chat return canned strings | Needs a real model behind a server-side key |

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
such call goes through a Supabase Edge Function that authenticates the user,
checks their quota, and holds the API key. This single rule is why the 3D
endpoint, the LLM calls, and any future paid API all share the same shape.

An API key shipped inside an APK is a public key. Anyone can `unzip` the
bundle, pull the string out, and spend your GPU credits.

## Document index

Read [12](12-poi-sources-and-ingestion.md) early — it defines where location
data comes from, so it logically precedes 02 and 08. It's numbered last only
to keep existing cross-links stable.

| # | Document | Covers |
| --- | --- | --- |
| 12 | [POI sources & ingestion](12-poi-sources-and-ingestion.md) | Maps API comparison, tile cache, dedupe, interestingness scoring |
| 01 | [Auth & accounts](01-auth-and-accounts.md) | Anonymous-first sign-in, upgrade to email/OAuth, session handling, account deletion |
| 02 | [Cloud database schema](02-cloud-database-schema.md) | Full Postgres schema, PostGIS radius queries, RLS policies, migrations |
| 03 | [Local database schema](03-local-database-schema.md) | Drift/SQLite mirror, what's cached vs. authoritative, encryption |
| 04 | [Sync & caching](04-sync-and-caching.md) | Offline outbox, conflict resolution, cache tiers and TTLs |
| 05 | [Storage & media](05-storage-and-media.md) | Buckets, upload paths, signed URLs, thumbnails, local file lifecycle |
| 06 | [3D generation pipeline](06-3d-generation-pipeline.md) | Camera → job → `.glb` → viewer, end to end, plus fixes to the Modal function |
| 07 | [Securing the 3D endpoint](07-securing-the-3d-endpoint.md) | Concrete hardening of `backend/hunyuan2.1/api.py` |
| 08 | [LLM & AI features](08-llm-and-ai-features.md) | Free models for itinerary generation, chat, translation, moderation, embeddings |
| 09 | [Internationalization](09-internationalization.md) | ARB setup, RTL for Arabic, translating user-generated and seed content |
| 10 | [Theming — light & dark](10-theming-light-dark.md) | Migrating 224 static const references to a themeable system |
| 11 | [Security checklist](11-security-checklist.md) | Consolidated review, threat model, pre-launch gate |
| 12 | [POI sources & ingestion](12-poi-sources-and-ingestion.md) | *(listed above — read first)* |

## Suggested build order

Each phase leaves the app in a shippable state.

**Phase 1 — foundations (no user-visible change)**
Repository layer between `AppBloc` and data · Drift local DB · models get
JSON serialization · seed `allLocations` into SQLite instead of a Dart list.
Ship it: the app behaves identically but now survives being killed.

**Phase 2 — accounts and cloud**
Supabase project · schema + RLS · anonymous auth on first launch · sync engine
for saved locations, trips, points. Ship it: progress follows the user.

**Phase 3 — real POI data**
Ingestion Edge Function · tile cache · dedupe · interestingness scoring ·
Wikidata/Wikipedia/Commons enrichment. Ship it: the map covers real geography
instead of 8 hardcoded points, and the radius slider works.

**Phase 4 — LLM selection**
The model layer on top of phase 3's candidates, plus the chat surfaces. This
is deliberately *after* ingestion: without scored candidates there's nothing
worth prompting a model about.

**Phase 5 — the 3D feature**
Harden the Modal endpoint · Edge Function proxy · job table · camera flow ·
real `.glb` viewer replacing the photo cube.

**Phase 6 — polish**
i18n · dark mode.

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
