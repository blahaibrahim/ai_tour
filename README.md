# Massar — مسار

**An AI-guided tour companion for Algeria that turns travellers into contributors to a 3D record of the country's heritage.**

> **Status: MVP.** This repository is a working minimum viable product, not a
> shipped commercial product. The core loop runs end to end on real devices
> against real data. Scope limits and known gaps are documented honestly in
> [MVP scope and known limits](#mvp-scope-and-known-limits) rather than left for
> the reader to discover.

> **Submitted to *AI Tour Algeria 2026*** — Ministry of Tourism and Handicrafts.
> **Axis 01 — Dream (Rêve):** immersion, augmented reality, 3D modelling
> (NeRF/3DGS-class reconstruction), and generative content.

---

## Table of contents

- [The idea](#the-idea)
- [Why it fits Axis 01](#why-it-fits-axis-01)
- [System structure — three applications](#system-structure--three-applications)
- [1. Massar Mobile — the Flutter app](#1-massar-mobile--the-flutter-app)
- [2. Massar Web — the browser companion](#2-massar-web--the-browser-companion)
- [3. Massar Studio — the pipeline CLI and its dashboard](#3-massar-studio--the-pipeline-cli-and-its-dashboard)
- [Shared services](#shared-services)
- [Repository map](#repository-map)
- [Running it](#running-it)
- [Configuration](#configuration)
- [Technology](#technology)
- [Testing](#testing)
- [MVP scope and known limits](#mvp-scope-and-known-limits)
- [Ethics, privacy and data sovereignty](#ethics-privacy-and-data-sovereignty)
- [Intellectual property](#intellectual-property)

---

## The idea

A traveller says where they are going, what they are interested in, and how long
they have. Massar generates an ordered walking or driving route through real
points of interest, then accompanies them along it — one task per stop, an AR
fennec hidden near each one, and a camera that turns what they photograph into a
keepable 3D artifact.

```
sign in (anonymous ok) → onboarding → pick city / theme / time budget
   → route generated → swipe to accept or drop each stop → travel the route
   → per-stop quest (photo · video · fennec hunt) → capture
   → 3D reconstruction on GPU → artifact lands in the Folder
   → footage feeds the splat pipeline → traveller is notified when their
     contribution becomes a reconstruction of the site they visited
```

That last line is the part that makes Massar more than an itinerary app. Every
traveller who films a slow pan at Djemila is contributing frames toward a
photogrammetric reconstruction of Djemila — and is told so, by name, when the
reconstruction is finished. The tourism product and the heritage-digitisation
programme are the same product.

### Design constraints that shaped the architecture

These are stated because they explain choices that would otherwise look odd:

- **No international payment card is available.** This rules out ARCore
  Geospatial, 8th Wall, paid background-geolocation plugins, and paid routing
  tiers. Every dependency in the stack is free without a card.
- **Offline-hostile geography is the point.** Djemila, Timgad, the Tassili
  plateau — the places worth touring are the places with no signal.
- **Mid-range Android is the device floor**, including devices with no ARCore,
  which is why the capture flow degrades cleanly to a plain camera.

---

## Why it fits Axis 01

| Article 2 — Dream axis | Implementation in this repository |
|---|---|
| Augmented Reality | AR fennec hunt with split client/server authority, proximity bands, bearing-preserving placement, server-side capture validation and anti-cheat |
| 3D Modelling (NeRF-class) | **Hunyuan3D** image→mesh on GPU (production path) and an **INRIA 3D Gaussian Splatting** video→splat pipeline (COLMAP SfM → 3DGS training) |
| Generative content | LLM-generated point-of-interest descriptions, per-stop quest generation, and grounded conversational chat about each place |
| Immersion | In-app GLB artifact viewer, WebGL splat viewer, AR overlay, and a collectible artifact folder |

Massar also has a legitimate claim on Axis 02 (conversational AI, smart
recommendation, personalised itineraries). It is submitted under Axis 01 because
the 3D reconstruction pipeline is the part that is genuinely uncommon, and
because Article 2 asks for one axis.

---

## System structure — three applications

Massar is three user-facing applications over one shared services layer. Each
one exists because it serves an audience the others cannot reach.

```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  1. MASSAR MOBILE   │  │  2. MASSAR WEB      │  │  3. MASSAR STUDIO   │
│  Flutter (Android/  │  │  Next.js browser    │  │  Python CLI +       │
│  iOS)               │  │  companion          │  │  Next.js dashboard  │
│                     │  │                     │  │                     │
│  Full experience:   │  │  Planning half:     │  │  Operator tool:     │
│  routes · AR hunt · │  │  routes · itinerary │  │  splat pipeline ·   │
│  quests · capture · │  │  · saved · points   │  │  analytics · splat  │
│  3D artifacts       │  │  No AR, no quests   │  │  publishing         │
│                     │  │                     │  │                     │
│  Traveller, on site │  │  Traveller, before  │  │  Massar operators   │
│                     │  │  the trip / no APK  │  │  (local only)       │
└──────────┬──────────┘  └──────────┬──────────┘  └──────────┬──────────┘
           │                        │                        │
           └────────────────────────┼────────────────────────┘
                                    ▼
             ┌──────────────────────────────────────────────┐
             │  SHARED SERVICES                             │
             │  Express/TypeScript API  ·  Supabase         │
             │  (Postgres + PostGIS + Auth + Storage +      │
             │   Realtime + RLS)  ·  Modal GPU services     │
             └──────────────────────────────────────────────┘
```

---

## 1. Massar Mobile — the Flutter app

**Path:** [`lib/`](lib/) · **Package:** `massar` · **Platforms:** Android, iOS

The complete experience. This is the application a traveller uses on site.

### Planning and route generation

- **Route request builder** over a map of Algeria — city, theme, optional
  category refinement, free-text prompt, time budget, and transport mode.
- **Time budget as days × hours-per-day** (1–4 days, 2–12 hours/day), because
  nobody plans a trip in minutes.
- **Transport mode**: walk, drive, or hybrid. A hybrid route returns drive legs
  between clusters and walk legs inside them; each segment is tagged with its
  own mode, so the client never has to infer it.
- **LLM prompt interpretation** — free text ("somewhere quiet with Ottoman
  architecture, not too much walking") is sent to `POST /api/routes/interpret`
  and turned into structured preferences.
- **Themes are filtered by availability** — the picker only offers a theme that
  has a published point of interest behind it in that city, so it cannot show a
  choice that can only fail.
- **Phased rollout is visible** — cities carry a rollout status; `planning`
  cities appear in the picker and say so rather than silently failing.
- **Generation is synchronous** and sub-second when warm.
- **Swipe deck** — accept or reject each generated stop, Tinder-style, with
  alternates on request.
- **Route refinement** re-runs clustering and ordering server-side rather than
  asking a language model to re-pick stops.
- **Grounded chat** — ask a question about any stop and get an answer grounded
  in that place's own data.

### On the route

- **Overview screen** — current stop, current quest, inline mascot hunt, and the
  upcoming stops row.
- **Per-stop quests**, one drawn per stop from three types: photo, video, and
  mascot hunt. Each is worth 30 points. Regeneration is capped, because with
  three types the third re-roll has nothing honest left to offer.
- **Location-verified scoring** — a completion is checked against the stop's own
  checkpoint radius. A completion that cannot be placed scores 10 instead of 30
  and does not reach the spendable wallet, so a catalogue containing real
  objects is not farmable from a sofa.
- **Progress and checkpoints** persist across cold starts.

### The AR fennec hunt

Massar's mascot is a fennec fox hidden near each stop.

- **Split authority** — the server owns *where* a mascot is (coordinates,
  capture radius, identity, reward); the client owns *how high* it sits and how
  it anchors, from plane detection. Neither side can produce a correct placement
  alone.
- **Distance is computed entirely on-device** from a cached spawn manifest. The
  server is consulted twice per mascot — fetch manifest, validate capture — which
  is what lets the hunt work with no signal and keeps server calls proportional
  to mascots rather than to GPS fixes.
- **Proximity bands** drive hot/cold feedback with hysteresis, and **adaptive GPS
  sampling** ties fix rate to the current band to protect battery.
- **Bearing-preserving placement, not geo-anchoring.** Consumer GPS is accurate
  to ±5–15 m and urban compass error runs ±10–15°, so placing a model at its
  true coordinate 20 m out would put it inside a wall as often as not. Once
  inside the capture radius the fennec is placed at a fixed comfortable distance
  along the true bearing and snapped to the detected floor.
- **Server-side capture validation** — a signed capture token with a 5-minute
  TTL, a per-attempt nonce for idempotency, and a position and accuracy check.
- **Graceful degradation** — devices without ARCore fall back to non-AR capture
  rather than losing the feature.

### Capture and 3D reconstruction

One viewfinder, two modes, swiped between above the shutter.

- **Media mode** — keep the photo or clip, with replay before filing.
- **Scan mode** — send the frame to be rebuilt as a 3D model.
- **On-device pre-flight** — ML Kit image labelling rejects an unusable frame (a
  blank wall, the sky, the floor) *before* it costs GPU time.
- **Reconstruction pipeline** — upload to storage → artifact row → generation
  request → Hunyuan3D on GPU → job reaches a terminal state → a database trigger
  fires a webhook → push notification. The app also subscribes over Realtime for
  the foreground case.
- **Metered credits** with honest refunds: an infrastructure failure refunds the
  credit; a "no subject in frame" result does not, because it consumed real GPU
  time and the traveller can simply retake the photo.
- **Artifact viewer** opens each artifact as what it is — GLB viewer, video
  player, pan-and-zoom photo, or a rotating placeholder when there is no media.
- **Media cache** downloads finished models once and serves them from disk
  permanently, since they are large and immutable.

### Rewards and points

- **Two balances by design** — a lifetime `total_points` that establishes rank
  and a separate spendable wallet, because spending what you earn must not cost
  you your standing.
- **Rewards catalogue** with digital rewards live today; partner vouchers and a
  physical tier are specified and schema-backed.
- **Atomic spending** — a single database function is permitted to debit, under
  a row lock, idempotent, with each distinct refusal carrying its own error code
  so the app can tell the traveller the true reason.

### Notifications

Four kinds, each independently opt-outable: `route_ready`, `model_ready`,
`mascot_nearby`, and `splat_ready`. Quiet hours are evaluated in the traveller's
local time. Duplicate suppression and rate limits are enforced on both the
device and the server, against the same rules.

### Localisation

**Complete in three languages — English, French, and Arabic** — with 459
translated strings and no missing keys in any locale.

- **Full RTL support for Arabic**, not a translation pass. Layout is directional
  throughout; no physical left/right insets remain in the codebase.
- **What deliberately does not mirror:** the map (geography is not directional),
  the compass, AR and 3D views (world space, not layout space), and the swipe
  gesture itself.
- Typefaces swap with the locale, and the theme rebuilds on a language change so
  the switch takes effect without a restart.

### Resilience

- **Backend reachability** is tracked as a side effect of real traffic rather
  than by polling. When the backend is unreachable, every repository serves a
  curated eight-place Algeria fallback rather than a blank screen.
- **Offline points outbox** replays quest completions recorded without signal.
- **Session state** — screen, route, progress, points — survives a cold start.
- **Image caching** persists to disk across restarts, with prefetch ahead of the
  swipe deck.

---

## 2. Massar Web — the browser companion

**Path:** [`website/massar_web/`](website/massar_web/) · **Stack:** Next.js 16, React 19, TypeScript, Tailwind 4, Leaflet

A browser mirror of the app's **planning half**. It exists because a foreign
tourist researching Algeria before a trip will not install an APK, and because a
jury, a partner, or a ministry reviewer should be able to see the product work
without provisioning a device.

**Included:** authentication, route generation, the generated itinerary and its
map, route overview, saved places, points, and settings — rendered against the
same API and the same design language as the mobile app.

**Deliberately excluded:** the AR hunt, quests, and camera capture. Those need a
phone in a place, and a browser simulation of them would misrepresent what the
product does.

---

## 3. Massar Studio — the pipeline CLI and its dashboard

**Path:** [`backend/gaussian_splatting/`](backend/gaussian_splatting/) (CLI) and
[`website/gaussian_splatting/`](website/gaussian_splatting/) (dashboard)

The operator surface: a staged command-line reconstruction pipeline, plus a
local web front end that drives it and publishes its results back to travellers.

### The CLI — video to Gaussian splat

```
video ──▶ frames ──▶ COLMAP SfM ──▶ 3DGS training ──▶ point_cloud_7000.ply
          (CPU)        (CPU)            (L4 GPU)
```

Run as `--stage build | frames | sfm | train | all`. The staging is a cost
decision, not tidiness: structure-from-motion is the slowest step and by far the
likeliest to fail, so it runs on cheap CPU and acts as the correctness gate
before any GPU money is spent. The GPU stage refuses to start without an
explicit `--yes`, and every run prints a cost estimate before spending.

Output is standard INRIA 3DGS `.ply`, readable by superspl.at, PlayCanvas,
Postshot, and the antimatter15 viewer.

### The dashboard — analytics, studio, and publishing

Two tabs:

- **Overview** — live analytics: explorers, stops, routes, captures, model jobs,
  storage consumption, and the splat pipeline's own funnel.
- **Studio** — a capture on one side and what reconstruction made of it on the
  other. Left: wilaya → its stops → footage recorded there, on a pannable,
  zoomable SVG map of Algeria. Right: the clip player, cached stages, run cost,
  live log, and the splat itself in a WebGL canvas. One selection drives both
  halves and lives in the URL, so any clip or splat can be linked directly.

**The publishing step closes Massar's loop.** When a splat trained from a
traveller's footage is good enough to show, the operator publishes it from the
Studio, which sends that traveller a `splat_ready` notification deep-linking to
the reconstruction their own recording helped build.

Two properties worth knowing:

1. **It is local-only by design.** It reads with a service-role key — the
   numbers it shows are exactly what row-level security hides from anonymous
   clients. The browser only ever receives aggregates and short-lived signed
   URLs. This is why it is an operator tool and not a deployed site.
2. **Everything that spends money is still a `modal` child process.** There is
   no second implementation of any pipeline stage here, which is what keeps the
   dashboard and the CLI from ever disagreeing about a result.

Wilaya assignment is done server-side by point-in-polygon against the same
GeoJSON boundary file the Flutter app draws its map from, so the two surfaces
cannot disagree about a border.

---

## Shared services

### API — `backend/server-node/`

Express + TypeScript, Node ≥ 20, a single process on port 8000.

| Group | Endpoints |
|---|---|
| Health | `GET /api/health` |
| Catalogue | `GET /api/cities`, `GET /api/categories` |
| Routes | `POST /api/routes`, `GET /api/routes/:id`, `POST /api/routes/:id/refine`, `POST /api/routes/interpret`, progress and checkpoint endpoints |
| Mascots | generate · list · proximity · capture · batch capture · asset · collection |
| Models | `POST /api/models/generate` |
| Chat / Quests | `POST /api/chat`, `POST /api/tasks/generate` |
| Notifications | push-token register/remove, prefs read/write, internal job-notify webhook |
| Ingestion | `POST /api/poi/ingest` |
| Auth | `POST /api/auth/delete-account` |

**Route generation** is five layers — adapters, data, domain, orchestration,
API — implementing K-Means clustering with a DBSCAN fallback, travelling-salesman
ordering, segment estimation against the time budget, and an isochrone
reachability check that decides whether a route genuinely needs more than one
day. Routing runs through a provider adapter (GraphHopper primary,
OpenRouteService documented as an alternate) with a straight-line estimator as a
declared fallback that announces itself on every request rather than pretending.
A cache layer — Redis when configured, in-memory otherwise — is the difference
between a first route costing ~15 s and ~0.5 s.

**Theme vocabulary lives in the database**, not in TypeScript, with per-city
overrides. It is configuration, not code.

**AR capture** covers the mascot catalogue, per-stop AR content, deterministic
spawn generation, manifest delivery, capture validation, and collection state.

**Ingestion** is the discovery pipeline: OpenStreetMap via Overpass → Wikidata →
Wikipedia → Wikimedia Commons photos → scoring → tiling → LLM description.

Both route generation and AR capture have a **fixture mode**, so the entire app
can be developed with no database and no network.

### Data — Supabase

Postgres with PostGIS, plus Auth, Storage, Realtime, `pg_cron`, and `pg_net`.

- **Catalogue:** cities, points of interest, categories, regions, themes,
  routes, stops, and progress. **Pilot data: 3 cities — Algiers, Oran,
  Constantine — and 35 published points of interest, 24 with a licensed and
  attributed photograph.** The remainder render the fennec placeholder rather
  than borrowing a photograph of somewhere else.
- **AR:** mascots, spawns, captures, collection, and per-stop AR content.
- **User data:** profiles, artifacts, model jobs, saved places, quest
  completions, swipe decisions, chat messages, push tokens, notification
  preferences and log, rewards and redemptions.
- **Row-level security scopes every user-owned row and storage object** to the
  authenticated user.
- **Automation:** profile provisioning on sign-up, trigger-maintained point
  totals, the model-job notification webhook, and scheduled jobs that purge
  stale anonymous users, orphaned storage objects, and stuck jobs.

### GPU — Modal

- **`backend/hunyuan2.1/`** — the production image→3D service. Failures are
  mapped onto a fixed set of error codes the app has real copy for, so a
  traveller is never shown a stack trace.
- **`backend/gaussian_splatting/`** — the video→splat pipeline described above.

---

## Repository map

| Path | What it is |
|---|---|
| [`lib/`](lib/) | **Application 1** — the Flutter mobile app |
| [`website/massar_web/`](website/massar_web/) | **Application 2** — the Next.js browser companion |
| [`backend/gaussian_splatting/`](backend/gaussian_splatting/) | **Application 3a** — the staged splat pipeline CLI |
| [`website/gaussian_splatting/`](website/gaussian_splatting/) | **Application 3b** — Massar Studio, the CLI's dashboard |
| [`backend/server-node/`](backend/server-node/) | The shared API — Express + TypeScript |
| [`backend/hunyuan2.1/`](backend/hunyuan2.1/) | Modal GPU service — image → 3D mesh |
| [`backend/routing_tourAI-main/`](backend/routing_tourAI-main/) | Standalone reference implementation of the route module, and the specification the shared API's route layer was built against. Not deployed |
| [`supabase/`](supabase/) | Migrations, rollbacks, seed data, email templates |
| [`packages/ar_flutter_plugin_2/`](packages/ar_flutter_plugin_2/) | Vendored AR plugin |
| [`tool/poi_seed/`](tool/poi_seed/) | Catalogue seeding scripts |
| [`test/`](test/) | Flutter test suite |
| [`docs/`](docs/) | Architecture and module specifications |

---

## Running it

### Shared API

```bash
cd backend/server-node
npm install
npm run dev          # :8000
```

### Application 1 — mobile

Requires a `.env` at the repository root. On a physical device, `API_BASE_URL`
must be the host machine's LAN address, not `localhost`.

```bash
flutter pub get
flutter run

# release build for distribution
flutter build apk --release --split-per-abi
```

### Application 2 — web

```bash
cd website/massar_web
npm install
npm run dev          # :3000
```

### Application 3 — pipeline CLI and Studio

```bash
# CLI — staged, with a cost estimate before any GPU spend
cd backend/gaussian_splatting
modal run modal_app.py --stage build          # verify images only
modal run modal_app.py --stage sfm            # CPU correctness gate
modal run modal_app.py --stage train --yes    # GPU training

# Studio dashboard (requires website/gaussian_splatting/.env.local)
cd website/gaussian_splatting
npm install && npm run dev                     # :3000
```

---

## Configuration

**Mobile** — `.env` at the repository root: `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`API_BASE_URL`, `AR_TESTING_MODE`. Every value has a fallback, so a missing
`.env` is not a fatal error.

> ⚠️ This file is bundled into the built application package and ships to every
> device. It must contain only public, RLS-protected values. It is never a place
> for a service key.

**API** — `backend/.env`, documented exhaustively in `backend/.env.example`. The
two that matter most on a fresh checkout are `ROUTE_GENERATION_MODE` and
`AR_CAPTURE_MODE`; both default to `fixture` when unset, which is why a fresh
clone serves sample data until they are configured.

**Studio** — `website/gaussian_splatting/.env.local`, which holds a service-role
key and must never be deployed to a public host.

---

## Technology

| Layer | Choice |
|---|---|
| Mobile | Flutter · BLoC · flutter_map · geolocator · camera · ML Kit · flutter_3d_controller · Firebase Messaging |
| Web | Next.js 16 · React 19 · TypeScript · Tailwind 4 · Leaflet |
| API | Node ≥ 20 · Express · TypeScript |
| Data | Supabase — Postgres · PostGIS · Auth · Storage · Realtime · RLS · pg_cron · pg_net |
| Routing | GraphHopper, with a declared straight-line fallback |
| 3D | Hunyuan3D (image → mesh) · COLMAP + INRIA 3D Gaussian Splatting (video → splat) |
| GPU | Modal (NVIDIA L4) |
| Language models | Open-weight models via a hosted inference API, with a second open-weight tier as fallback |

---

## Testing

**Mobile** — 17 test files, concentrated deliberately on the places where being
wrong is *invisible* rather than on the places that are easy to test: AR camera
pose, AR placement, geographic maths, heading conversion, proximity bands,
spawn-point generation, quest types, the review budget gate, route legs, image
sizing, wilaya selection, artifact naming, notification policy, rewards, and two
widget tests.

Among these is a **parity test that asserts the client's proximity-band
calculator agrees with the server's** — the class of bug that produces a fennec
that is "hot" on the phone and out of range on the server.

**API** — `npm test` covers point-of-interest rules, AR capture, and route
generation, including a live end-to-end generation for every theme. The suite
forces estimate-mode routing itself, so an automated run can never consume
free-tier API quota.

```bash
flutter test                              # mobile
cd backend/server-node && npm test        # API
```

---

## MVP scope and known limits

Stated plainly, because a reviewer will find these anyway and an honest list is
worth more than a discovered one.

**Pilot scale.** 3 cities and 35 published points of interest. The ingestion
pipeline to expand this is built and tested; the catalogue is a data problem, not
an engineering one.

**Offline is incomplete.** Session state, a points outbox, cached imagery, and
an on-device AR hunt work without signal. There is no local database, so route
planning and catalogue browsing still require a connection. Given that Massar's
best destinations are its least connected, this is the most important item on
the roadmap and is specified in `docs/`.

**Gaussian splat publishing is operator-triggered.** Reconstruction quality
still varies enough with input footage that a human decides what is worth
showing a traveller. Automating that gate needs a quality metric that does not
exist yet.

**iOS push notifications are not configured.** Android is complete. iOS
notifications work while the app is running.

**Video quests are assigned but not yet completable** — the capture screen
currently offers photo and 3D scan.

**Rate limiting currently fails open** on a database error, and anonymous
sign-up is not itself rate-limited. Both are known and both are small fixes.

**The mascot collection album and partner voucher redemption** are schema-backed
and endpoint-complete, without their final screens.

---

## Ethics, privacy and data sovereignty

Addressing Article 10 directly.

**Personal data.** Massar processes location, camera captures, and device push
tokens. Location is used to place AR content and verify quest completion;
captures are used to produce the traveller's own artifacts and, with consent, to
contribute to heritage reconstructions. Row-level security scopes every
user-owned row and storage object to its owner. Anonymous use is first-class —
the app is usable without ever providing an email address — and anonymous
accounts are purged automatically on a schedule.

**Security.** AR captures are validated server-side with a signed, short-lived
token and a per-attempt nonce, so points cannot be claimed by a modified client.
Credit-consuming database functions are locked down against direct execution.
The operator dashboard's privileged key never reaches a browser.

**Bias.** The most material bias in this system is in point-of-interest
selection: an ingestion pipeline drawing on OpenStreetMap, Wikidata, and
Wikimedia Commons will systematically favour sites that are already
well-documented and well-photographed, which skews toward the northern cities and
away from the south. This is recognised, it is a data problem rather than a
model problem, and interest scoring is explicitly separated from source richness
so the two can be corrected independently. Generated content is grounded in each
place's own record rather than free-form, which bounds what a language model can
invent about a site of cultural or religious significance.

**Sovereignty.** All 3D reconstruction is **open-weight and self-hosted** —
Hunyuan3D and INRIA 3D Gaussian Splatting, running on GPU infrastructure Massar
operates rather than a proprietary reconstruction API. The language layer
currently uses a hosted inference API, with an open-weight tier already
implemented and running as its fallback. Data is stored in Supabase, which is
open source and self-hostable. **No component of this stack requires a
proprietary model or a foreign host as a matter of architecture** — hosting is an
operational choice, and migration to Algerian infrastructure (a self-hosted
database and a national GPU or inference platform) is a deployment change rather
than a rewrite.

---

## Intellectual property

Copyright is retained by the authors, per Article 9 of the competition rules.
Point-of-interest photographs are sourced from Wikimedia Commons and carry their
individual licences and attribution in the database alongside each record.
