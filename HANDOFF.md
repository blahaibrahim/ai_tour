# AI Tour — Handoff

Project-level status. For backend specifics read
[docs/backend/HANDOFF.md](docs/backend/HANDOFF.md); for the design reasoning
behind any decision read the numbered docs in [docs/backend/](docs/backend/),
**starting from each one's `> **Status:**` note**, which is authoritative where
the prose beneath it has gone stale.

---

## Where the project stands

The product loop works end to end, on real data, from a real device:

**Anonymous sign-in on launch → map + radius → prompt → async route generation
(live Overpass → deterministic ranking → LLM selection → OSRM ordering) →
swipe to accept/reject → route editing by natural language → per-stop tasks →
AR capture → 3D model generation on Modal → GLB in the artifact viewer.**

Everything the app shows now comes from a real backend. There are no canned
responses left in `AppBloc`, and the Flask server, Supabase project, and Modal
worker are all live and authenticated.

### What changed from the original plan

Four divergences matter more than the rest, because they invalidate parts of
the design docs:

1. **Route generation calls Overpass live, per request** — it does not read the
   `locations` catalogue, which is currently empty. Location ids are
   `osm-node-123`, not uuids. (Docs 12, 13.)
2. **Itinerary generation is asynchronous** — `POST /api/itinerary` returns a
   `job_id`; the client polls. No design doc anticipated this.
3. **The trusted server is Flask**, not Supabase Edge Functions. Everywhere a
   doc says "Edge Function," read "Flask route."
4. **The schema shrank** — `trips`, `trip_stops`, `chat_messages` and
   `swipe_decisions` were dropped as unused. An accepted route now lives only
   in `route_jobs.result_data`.

---

## Features remaining before a UI overhaul

Ordered so that everything which would otherwise force a **second** pass over
the same screens comes first. The rule used throughout: *if it changes what a
screen must display, or how it must lay out, it belongs before the overhaul.*

### A. Correctness blockers — fix first, they are not design problems

An overhaul would re-skin these without fixing them, and they'd read as new
bugs afterward.

1. **"Ask about this place" and task regeneration 404 on every real stop.**
   Both backend routes resolve the location through the empty catalogue, while
   the app sends `osm-*` ids. The user sees "Sorry, I couldn't reach the guide"
   and a silently-recycled hardcoded task. `ChatRepository.askAboutPlace`
   already sends `location_name` and `blurb` — the backend just ignores them.
   *(Doc 08.)*
2. **Route-generation failure has no UI.** `AppState.routeError` exists, and
   nothing ever sets it: `LocationRepository.generateItinerary` swallows every
   exception and returns `[]`. A failed generation is indistinguishable from
   "no places nearby" — the user lands on an empty swipe screen with no
   explanation and no retry.
3. **Two schema objects exist only in the live database.** `route_jobs` and the
   recreated `saved_locations` have no committed migration; two committed
   migrations aren't in the applied ledger. The repo cannot rebuild the project
   it documents. *(Doc 02.)*
4. **Rate limiting fails open.** `rate_limit.py` swallows any error from
   `check_rate_limit`, so a DB hiccup grants unlimited access to every LLM and
   GPU endpoint. With unlimited free anonymous sign-up, quota is advisory.
   *(Doc 11 #10, #11.)*

### B. Data that exists but never comes back — decide the model before designing screens

Each of these already persists correctly to Supabase. Nothing reads it back, so
the screen that should show it can't be designed yet.

5. **Generated 3D artifacts vanish on restart.** `artifacts` (12 rows) and the
   `.glb` files in Storage are written and never read — `lib/repositories/model_repository.dart`
   inserts, nothing selects. The folder rebuilds from in-memory state and pads
   with hardcoded `exampleArtifacts`. **The folder screen's real content is
   undefined until this exists**, which makes it impossible to design honestly.
6. **Saved locations persist but can't be re-displayed.** `saved_locations`
   stores the ids, but `folder_screen.dart:56` resolves them only against
   locations currently in memory. After a restart there is no way to fetch an
   `osm-*` location by id, so the Saved tab is empty forever. Needs either a
   POI-by-id endpoint or denormalized location data on the row.
7. **Points, tasks, and trip dates are in-memory only.** The trip date picker
   writes to `AppState` and nowhere else (`trips` was dropped). Points reset to
   zero on every launch. Decide whether these are real features or should come
   out of the UI.
8. **No retry for a failed 3D job.** The folder shows the failure state; nothing
   re-submits. *(Doc 06.)*

### C. Foundations that touch every screen — the strongest argument for doing them first

9. **Theming (doc 10).** 241 `AppTheme.` static-const references across 34
   files, one light theme, no `ThemeMode`. A static const cannot change at
   runtime, so dark mode is a migration of all 241, not a toggle. **Doing the
   UI overhaul first means doing this migration twice** — once on the old
   widgets, once on the new. Land the `ThemeExtension` structure first and the
   overhaul builds on it for free.
10. **i18n + RTL (doc 09).** No ARB files, no `flutter_localizations`,
    `locale='en'` hardcoded backend-wide. Arabic is the primary market language
    and brings RTL with it. **RTL is a layout constraint, not a translation
    task** — retrofitting it into freshly-designed screens is materially harder
    than designing with it. If Arabic is in scope at all, this belongs before
    the overhaul, not after.
11. **Offline / local database (docs 03, 04).** No Drift, no local mirror, no
    outbox. Every screen requires the network, at Djemila and Timgad and on the
    Tassili plateau where there isn't any. This determines every loading, empty,
    stale, and error state the new UI has to render — design those without it
    and they get redesigned later. Phase 1 of the original plan was skipped;
    this is the retrofit bill.

### D. Features with no UI at all yet — new screens the overhaul should scope

12. **Account upgrade (doc 01).** Anonymous sign-in works; there is no path to
    a real account. No sign-in screen, no `linkIdentity`, no
    `updateUser(email)`, no OAuth. Every user loses everything on reinstall.
13. **Account deletion.** `POST /api/auth/delete-account` is implemented and
    unreachable — nothing in `lib/` calls it. Likely a store-review requirement.
14. **The Settings screen is a mockup.** Eight of its nine tiles have no
    `onTap`: Profile details, AI Tour Pro, Notifications, Offline Maps,
    Language, Help Center, Privacy Policy. Only "Leave Current Tour" works.
15. **Folder thumbnails.** The `thumbnails` bucket exists, is configured, and
    nothing writes to it; the grid renders full captures or an animated cube.
    *(Doc 05.)*

### E. Deliberate loose ends — decide, don't inherit

16. **The POI catalogue is half-retired.** `locations`, its embeddings, its
    fr/ar translations, `describe.py`'s blurb work, `rewrite.py`,
    `nearby_locations`' semantic ranking, `extract_intent()`,
    `_expand_categories()`, and `scripts/ingest_geofabrik.py` are all built and
    all currently serve nothing. Either give the catalogue a job (it's the only
    home for semantic search and translated content — see item 10) or retire it
    and delete what depends on it. Leaving it is the worst option.
17. **The 8-stop route length is hardcoded**, ignoring the client's
    `wantedVisits`; trip duration and travel mode aren't accepted by the API at
    all. *(Doc 13.)*
18. **Capture paths break on reinstall.** Captures outside the 3D flow are
    still stored by absolute path. *(Doc 11 #6.)*

---

### Recommended sequence

**A → C(9) → B → C(10, 11) → UI overhaul → D**

Group A is small and stops the app misbehaving. Item 9 (theming) is the single
highest-leverage pre-overhaul task — it is pure structure, it can't be done
cheaply afterward, and every new widget written before it is written wrong.
Group B defines what the folder and saved screens actually contain, which the
overhaul needs to know. Items 10 and 11 set layout direction and the full set
of loading/empty/error states.

Group D is the one group that arguably belongs *inside* the overhaul rather
than before it — those are new screens, and designing them fresh alongside the
rest is cheaper than building them twice.

---

## Running it

**Backend:**
```bash
cd backend/server
venv/Scripts/python.exe app.py     # serves on :8000
```

**App:** needs `.env` at the repo root with `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, and `API_BASE_URL` (defaults to `http://localhost:8000`;
use the host machine's LAN IP for a physical device).

```bash
flutter run
```

Backend env vars are documented in `backend/.env.example`. All of them are
currently set and working — see docs/backend/HANDOFF.md for the list and for
the two things that env file cannot prove (the Modal spend limit and function
timeout).
