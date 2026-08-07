# AI Tour — Backend Implementation Plan

These docs describe how to take the app from its original state — a single
in-memory `AppBloc` seeded from `lib/models/location_data.dart`, plus an
unauthenticated GPU endpoint in `backend/hunyuan2.1/` — to an account-based,
offline-capable, multilingual product with a secured 3D generation pipeline.

**Most of this plan is now built.** A Flask server at `backend/server/`, a live
Supabase project, and a hardened Modal service back the whole product loop —
route generation, place chat, task generation, 3D artifact capture — and the
Flutter app calls all of it. What remains is mostly the *offline and polish*
half of the plan (docs 03, 04, 09, 10) plus a short list of real defects.

**These documents were written before any code existed**, and in several
places the implementation deliberately went a different way. Each doc carries
a `> **Status:**` note at the top saying what is actually true; **the status
note is authoritative and the prose beneath it often is not.** The largest
divergences, in order of how much they change the mental model:

1. **Route generation no longer reads the `locations` catalogue** — it queries
   Overpass live, per request. Docs 12 and 13 describe the ingest-then-query
   design that this replaced. Location ids are `osm-node-123`, not uuids.
2. **Itinerary generation is asynchronous** — `POST /api/itinerary` returns a
   `job_id` and the client polls. No doc predicted this; it fell out of the
   real latency.
3. **The trusted server is Flask, not Supabase Edge Functions.** Wherever a
   doc says "Edge Function," read "Flask route."
4. **The schema shrank.** `trips`, `trip_stops`, `chat_messages` and
   `swipe_decisions` were dropped as unused (doc 02).

**Picking up this work?** Read [HANDOFF.md](HANDOFF.md) first — a
current-state snapshot written for an agent starting a new session, rather
than these documents' original design intent.

---

## Where the app is today

| Area | Current state |
| --- | --- |
| State | One `AppBloc`, all state in memory. Survives a kill only for the route itself, by re-fetching `route_jobs` on launch (`ResumeRouteEvent`). Everything else — points, tasks, captured artifacts — is lost |
| Auth | **Anonymous sign-in on first launch**, session in the platform keychain, JWT on every request. No upgrade path to a real account (doc 01) |
| POI data | **Live Overpass per request**, hedged across three mirrors with a 10-minute bbox cache. The `locations` catalogue still exists and is still ingestible via `POST /api/poi/ingest`, but is **currently empty and out of the request path** (doc 12) |
| Route generation | **Async job.** Overpass candidates → deterministic ranking → LLM selection (Groq-first, ~1.6s) → OSRM travel-time matrix → greedy nearest-neighbour ordering, with photo lookups running underneath the model call |
| AI features | Itinerary + modify **working**. Chat and task generation are wired but **404 on every generated stop** — they look up `osm-*` ids in the empty catalogue (doc 08) |
| 3D generation | **Complete end to end.** On-device labelling → compress + EXIF strip → upload → authed, quota'd, deduped Flask proxy → Modal worker → `.glb` in Storage → Realtime → native `Flutter3DViewer` |
| Artifact viewer | Real GLB renderer. The photo-textured cube survives only as placeholder and grid thumbnail |
| Persistence | No local database. Captures outside the 3D flow are still referenced by absolute path (doc 11 #6) |
| Offline | None. Every screen needs the network (docs 03, 04) |
| i18n | None. `locale='en'` hardcoded backend-wide; no ARB files; no RTL (doc 09) |
| Theme | **241** references to `AppTheme.` static consts across 34 files, single light theme (doc 10) |

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
1. FETCH   Overpass → tourism POIs near the user   (hedged mirrors, 10-min bbox cache)
2. SCORE   Deterministic ranking — is this worth visiting at all?
3. SELECT  LLM picks from the top 30 candidates, per the user's prompt
4. ORDER   OSRM travel-time matrix → greedy nearest-neighbour
```

The model never invents a place; it only chooses from rows a maps provider
vouched for, and any id it returns that isn't in the candidate set is dropped.
Stage 2 is where the product lives — raw POI feeds return the Casbah alongside
gift shops and car parks, and filtering that cheaply before the model sees it
is both a quality and a cost decision. Stage 4 is never asked of the model:
geometry chooses the order.

**Stage 1 changed after these docs were written.** [12](12-poi-sources-and-ingestion.md)
describes fetching into the `locations` catalogue ahead of time and querying
that; the request path now calls Overpass directly instead, because a city
nobody had ingested returned only the curated seeds. The ingestion pipeline
still exists and still works — it is simply no longer what a route request
reads. Full reasoning in the docstring at the top of
`backend/server/routes/itinerary.py`; the intended end-state pipeline is
[13](13-route-generation-architecture.md).

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
differs. Wherever a doc below says "Edge Function," read "Flask route" — the
security properties described still apply, just in a different runtime.
Doc 07's Edge Function proxy in front of Modal was built this way, as
`backend/server/routes/models.py`.

Flask holds the Groq key, the Gemini key, the Modal proxy key pair, and the
Supabase `service_role` key (`backend/server/ingestion/supabase_admin.py` —
kept deliberately separate from the `anon`-key client every read path uses,
`backend/server/data/supabase_client.py`). The rule holds in both directions:
the app reaches Modal only through Flask, and it ships no third-party key of
any kind.

**One deliberate exception:** `SavedLocationsRepository` writes to
`public.saved_locations` straight from the app rather than through Flask. Its
RLS policy already scopes every row to `auth.uid()`, so a server hop would add
nothing — and Supabase, unlike Modal or an LLM provider, is not a metered
third party the app would be spending on someone else's behalf.

## Document index

Read [12](12-poi-sources-and-ingestion.md) early — it defines where location
data comes from, so it logically precedes 02 and 08. It's numbered last only
to keep existing cross-links stable.

| # | Document | Covers | Status |
| --- | --- | --- | --- |
| 12 | [POI sources & ingestion](12-poi-sources-and-ingestion.md) | Maps API comparison, tile cache, dedupe, interestingness scoring | **Implemented — but out of the request path**, and the catalogue is empty |
| 01 | [Auth & accounts](01-auth-and-accounts.md) | Anonymous-first sign-in, upgrade to email/OAuth, session handling, account deletion | **Half implemented** — anonymous sign-in works; no upgrade path, delete-account unreachable |
| 02 | [Cloud database schema](02-cloud-database-schema.md) | Full Postgres schema, PostGIS radius queries, RLS policies, migrations | **Implemented, then cut back** — 5 tables dropped, 2 live tables have no committed migration |
| 03 | [Local database schema](03-local-database-schema.md) | Drift/SQLite mirror, what's cached vs. authoritative, encryption | Not started |
| 04 | [Sync & caching](04-sync-and-caching.md) | Offline outbox, conflict resolution, cache tiers and TTLs | Not started |
| 05 | [Storage & media](05-storage-and-media.md) | Buckets, upload paths, signed URLs, thumbnails, local file lifecycle | **Implemented for the 3D path**; `thumbnails` and `catalogue` unused |
| 06 | [3D generation pipeline](06-3d-generation-pipeline.md) | Camera → job → `.glb` → viewer, end to end, plus fixes to the Modal function | **Implemented end to end** |
| 07 | [Securing the 3D endpoint](07-securing-the-3d-endpoint.md) | Concrete hardening of `backend/hunyuan2.1/api.py` | **Implemented** — all four layers |
| 08 | [LLM & AI features](08-llm-and-ai-features.md) | Free models for itinerary generation, chat, translation, moderation, embeddings | **Implemented and wired** — chat + tasks 404 on an id-space mismatch |
| 09 | [Internationalization](09-internationalization.md) | ARB setup, RTL for Arabic, translating user-generated and seed content | Not started |
| 10 | [Theming — light & dark](10-theming-light-dark.md) | Migrating 241 static const references to a themeable system | Not started |
| 11 | [Security checklist](11-security-checklist.md) | Consolidated review, threat model, pre-launch gate | **Critical items closed**; fail-open rate limiting is now the weakest link |
| 13 | [Route generation architecture](13-route-generation-architecture.md) | Intent extraction, offline geo data, hybrid ranking, travel-time optimization | **Partially implemented** — back half built, intent/ranking layers dormant |

"Not started" means no Flutter or backend code exists for that doc yet — it's
still exactly a plan. Where a doc is marked implemented, **its own top-of-file
status note is authoritative** and gives the specifics; don't assume full
coverage from this table alone, and don't trust the prose under a status note
over the note itself.

## Build order — what happened, and what's left

The original plan ran phases 1→6 in order. **It didn't go that way**, and the
deviation is worth understanding before planning the next step: phases 2–5 were
built roughly together and phase 1 was skipped entirely.

| Phase | Plan | What actually happened |
| --- | --- | --- |
| 1 — foundations | Repository layer · Drift local DB · JSON serialization · seed into SQLite | **Half done, out of order.** The repository layer exists (`lib/repositories/`) and models serialize. **Drift was never added** — there is no local database, so the app still loses everything but the route on a kill, and works only online |
| 2 — accounts and cloud | Supabase project · schema + RLS · anonymous auth · sync engine | **Done except the sync engine.** Anonymous auth, 14 RLS-enabled tables, `saved_locations` persisted. No outbox, no offline writes — every user action needs the network |
| 3 — real POI data | Ingestion · tile cache · dedupe · scoring · enrichment | **Built, then bypassed.** All of it works; the request path now calls Overpass live instead and the catalogue sits empty (doc 12) |
| 4 — LLM selection | Model layer on phase 3's candidates, plus chat surfaces | **Done and wired to Flutter.** Chat and task generation are the exception — they still resolve ids against phase 3's catalogue, which is why they 404 (doc 08) |
| 5 — the 3D feature | Harden Modal · proxy · job table · camera flow · real `.glb` viewer | **Done end to end**, including the Realtime job updates and the native viewer |
| 6 — polish | i18n · dark mode | **Not started.** Neither exists |

**The cost of skipping phase 1 is now the main structural debt.** "Phases 1–2
are unglamorous but everything else sits on them" was right; everything else
got built anyway, so the offline foundation now has to be retrofitted under a
working app rather than laid before it. That is a bigger job than doc 03
describes, and it is the single largest item left.

## Immediate housekeeping

*(Resolved — kept as the record.)* `backend/**/venv/`, `__pycache__/`,
`*.pyc`, `results/`, `*.glb` and `.env` are all gitignored; nothing under
either venv is tracked. Doc 11 issue #3.

Two items **not** resolved, both from doc 02:

- `route_jobs` and the recreated `saved_locations` exist in the live database
  with **no committed migration**. The repo cannot currently rebuild the
  project it documents. Dump both and commit them before anything else needs a
  clean environment.
- `20260801120005_storage_and_auth_cron.sql` and
  `20260801120006_fix_stuck_jobs_cron.sql` are committed but not in the applied
  ledger, though their effects are live. Reconcile so `list_migrations` and
  `supabase/migrations/` agree.

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
