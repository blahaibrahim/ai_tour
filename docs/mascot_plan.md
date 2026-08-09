# AR Capture Module
## Technical Design Specification

**AR Tourism Platform — Axe Rêve Competition Project**
Version 1.0 • Mascot spawning, proximity hunt, and camera capture (server Layers 1–5 + client Layers C1–C5)

Companion document to *Route Generation Module — Technical Design Specification v1.0*. Where that document ends — an ordered route with per-POI checkpoint radii — this one begins.

---

## Contents

1. Purpose & Scope
2. Architecture Overview
3. Layer Responsibilities
4. System Workflow & Data Flow
5. Core Algorithms & AR Logic
6. APIs & External Services
7. Data Models & Key Interfaces
8. Feature Specifications
9. Implementation Roadmap & Development Order
10. Edge Cases & Assumptions
11. Basic Testing Strategy

---

## 1. Purpose & Scope

This document is the implementation specification for the **AR Capture module** — the component that hides one mascot near each POI on a generated route, guides the user to it with hot/cold proximity feedback (including while the app is backgrounded or terminated), and lets the user capture it through the camera with the mascot rendered standing on the real floor.

It is written to be used directly as build context: architecture, algorithms, data models, coordinate math, and build order.

### In scope

- **Server (Layers 1–5):** mascot catalog, per-POI AR content, spawn-point generation, spawn manifest delivery, capture validation and anti-cheat, collection/album state, push-notification policy.
- **Client (Layers C1–C5, Flutter):** proximity band state machine, adaptive location sampling, background geofence notifications, AR session lifecycle, ground-plane resolution, capture interaction.
- **Coordinate systems:** the WGS84 → ENU → AR-world transform, and the rule that **horizontal position is server-authoritative while vertical position is resolved on-device at runtime**.
- Web app's role in the AR feature (deliberately non-capture — see §10).

### Out of scope (deferred)

- Route generation itself — consumed as an input; see the companion spec.
- Authentication and user accounts — `user_id` fields are nullable, `session_id` carries anonymous demo usage exactly as in the route spec.
- Stamp/badge gamification rules beyond the capture event that feeds them (`pois.stamp_id` remains owned by the gamification module).
- Multiplayer, mascot trading, timed events, leaderboards.
- 3D asset authoring pipeline beyond the format and budget constraints stated in §6.

### Assumptions

- Mobile-first. Android is the primary target device population; iOS is supported but is the more constrained platform for background behaviour (§5.6).
- **No international payment card is available.** This is inherited verbatim from the route spec and it eliminates several otherwise-obvious choices: ARCore Geospatial API (requires Google Cloud billing), 8th Wall (paid), `flutter_background_geolocation` (paid licence). Every dependency named in §6 is free with no card.
- Feasibility and cost are explicit jury evaluation criteria; where a cheaper design is within 10% of the ideal one for this use case, the cheaper one is specified and the trade-off is stated rather than hidden.
- Target device floor: Android 8.0 / ARCore-supported device, or **graceful degradation to a non-AR capture mode** on devices without ARCore (§8, §10). This matters: a meaningful share of the Algerian mid-range device population is not on Google's ARCore-supported list.

---

## 2. Architecture Overview

Same layered modular monolith as the route module — the AR module is a set of new components **inside the existing service**, not a new service. It reuses the existing Routing Provider Adapter and Cache Adapter rather than introducing its own.

The important addition is that this feature has a **real client-side architecture**. The camera, the sensors, and the plane detection cannot live on the server, so the client gets its own five layers and its own contracts.

### Key design decisions

- **Split authority.** The server owns *where* a mascot is (latitude, longitude, capture radius, identity, reward). The client owns *how high* it is and *how it looks anchored* (Y from plane detection). Neither side can produce a correct placement alone, and neither ever guesses the other's half.
- **Client-side distance, server-side truth.** Hot/cold feedback is computed **entirely on-device** from a cached spawn manifest — no network round-trip per GPS fix. The server is consulted only twice per mascot: once to fetch the manifest, once to validate the capture. This is what makes the hunt work offline, keeps battery cost sane, and keeps the server call count at O(mascots) instead of O(GPS fixes).
- **Bearing-preserving AR placement, not survey-grade geo-anchoring.** Consumer GPS is ±5–15 m and urban compass error is ±10–15°. Placing a 3D object at its exact geographic coordinate 20 m away would put it inside a wall as often as not. Instead, once the user is inside the capture radius the mascot is placed at a **fixed comfortable distance along the true bearing** to the spawn point, snapped to the detected floor. Accuracy stops mattering at exactly the moment it stops being achievable. See §5.5.
- **Local notifications from geofences, not push.** The "you're getting hot" alert while the app is closed is a *local* notification fired by an OS geofence the client registered in advance. It needs no connectivity and no server. FCM push exists only for server-originated events (§6).
- **Degradation ladder, not a hard requirement.** AR-with-planes → AR-without-planes (estimated ground) → gyro overlay (no ARCore) → map-only capture. Every rung is playable. The feature never becomes a dead end on a weak device.
- **Never spawn on a road.** Spawn candidates are drawn from a curated per-POI polygon, not from a radius around a point. Safety is a design constraint, not a warning label (§5.1, §10).

### Figure 1 — Server-side layers (AR components in the existing monolith)

```
┌──────────────────────────────────────────────────────────────────────┐
│ Layer 1 — API                                                        │
│   AR Capture Controller                                              │
│   validation · rate limiting · idempotency keys · error translation   │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Layer 2 — Orchestration                                              │
│   Mascot Session Orchestrator                                        │
│   spawn-manifest assembly · capture pipeline sequencing · telemetry   │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Layer 3 — Domain                                                     │
│  ┌──────────────┐ ┌───────────────┐ ┌──────────────┐ ┌─────────────┐ │
│  │ Spawn Point  │ │ Proximity Band│ │   Capture    │ │ Notification│ │
│  │  Generator   │ │  Calculator   │ │  Validator   │ │   Policy    │ │
│  │ seeded, in   │ │ pure, mirrored│ │ distance +   │ │ cooldowns,  │ │
│  │ spawn zone   │ │ in Dart       │ │ plausibility │ │ quiet hours │ │
│  └──────────────┘ └───────────────┘ └──────────────┘ └─────────────┘ │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │ Collection Service — album state, first-catch, rarity rollup   │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Layer 4 — Adapter                                                    │
│  ┌────────────────┐ ┌──────────────┐ ┌───────────┐ ┌──────────────┐  │
│  │ Routing        │ │ Cache        │ │ Push      │ │ Asset Store  │  │
│  │ Provider       │ │ Adapter      │ │ Adapter   │ │ Adapter      │  │
│  │ (REUSED)       │ │ (REUSED)     │ │ FCM       │ │ signed URLs  │  │
│  └────────────────┘ └──────────────┘ └───────────┘ └──────────────┘  │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Layer 5 — Data                                                       │
│  AR Content Repo · Mascot Spawn Repo · Capture Repo ·                │
│  Collection Repo · Push Token Repo          (PostgreSQL / PostGIS)    │
└──────────────────────────────────────────────────────────────────────┘

Domain never imports an AR SDK, a push SDK, or a provider SDK — only the Adapter layer does.
```

### Figure 2 — Client-side layers (Flutter)

```
┌──────────────────────────────────────────────────────────────────────┐
│ C1 — Presentation                                                    │
│   Hunt screen (compass ring + thermometer + haptics)                 │
│   AR Camera screen (reticle, coaching overlay, capture animation)    │
│   Collection album  ·  Route map                                     │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ C2 — Game State                                                      │
│   HuntSessionController — band state machine, hysteresis, debounce,  │
│   capture-token lifecycle, notification cooldowns                    │
└──────────────────────────────────┬───────────────────────────────────┘
              ┌────────────────────┴────────────────────┐
              ▼                                         ▼
┌───────────────────────────────────┐  ┌──────────────────────────────┐
│ C3 — Sensors                      │  │ C4 — AR                      │
│  LocationService (adaptive rate)  │  │  ARSessionController         │
│  HeadingService (fused compass)   │  │  PlaneTracker · Raycaster    │
│  GeofenceService (OS regions)     │  │  MascotAnchor · CaptureProbe │
│  MotionService (speed / vehicle)  │  │  (platform channel → ARCore  │
└───────────────────────────────────┘  │   / ARKit)                   │
                                       └──────────────────────────────┘
              └────────────────────┬────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ C5 — Data                                                            │
│   Spawn manifest cache (SQLite/Isar) · Capture outbox queue ·        │
│   3D asset cache (.glb / .usdz, LRU, checksum-verified)              │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 3. Layer Responsibilities

### Server

| Layer | Component | Responsibility |
|---|---|---|
| 1 · API | AR Capture Controller | Validates requests, enforces per-user rate limits, honours idempotency keys on capture, translates domain errors to HTTP. |
| 2 · Orchestration | Mascot Session Orchestrator | Sequences Domain calls: manifest assembly on route start, capture validation pipeline, collection update, telemetry emission. Owns graceful degradation (a push failure never fails a capture). |
| 3 · Domain | Spawn Point Generator | Produces a deterministic, seeded, walkable spawn coordinate inside a POI's spawn zone. Pure given the zone geometry and seed. |
| 3 · Domain | Proximity Band Calculator | Maps distance → band with hysteresis. **Pure function, mirrored line-for-line in Dart**; a shared JSON fixture proves the two agree (§11). |
| 3 · Domain | Capture Validator | Distance check against the reported fix, accuracy gate, capture-token verification, teleport/replay plausibility, idempotency. |
| 3 · Domain | Notification Policy | Decides whether a server-originated push is allowed: per-mascot cooldown, per-day cap, quiet hours, user opt-out. |
| 3 · Domain | Collection Service | First-catch detection, rarity rollup, album projection. Emits the `progress_events` row that also satisfies the route module's checkpoint arrival. |
| 4 · Adapter | Routing Provider Adapter | **Reused.** Used at spawn-zone build time for pedestrian isochrones and walkability snapping. Never called on the request path. |
| 4 · Adapter | Cache Adapter | **Reused.** Caches spawn manifests per route and mascot catalog entries. |
| 4 · Adapter | Push Adapter | Wraps FCM. Single interface `send(tokens, payload)`. Fire-and-forget with retry; failures are logged, never propagated. |
| 4 · Adapter | Asset Store Adapter | Issues time-limited signed URLs for `.glb` / `.usdz` model files and returns their checksums. |
| 5 · Data | AR Content Repository | Per-POI AR configuration and spawn-zone polygons. PostGIS. |
| 5 · Data | Mascot Spawn Repository | Spawn instances per route. Immutable once generated, like `routes`. |
| 5 · Data | Capture Repository | Append-only capture attempts (accepted and rejected) — the anti-cheat audit trail. |
| 5 · Data | Collection Repository | User/session ↔ mascot album. |
| 5 · Data | Push Token Repository | Device push tokens, platform, last-seen. |

### Client

| Layer | Component | Responsibility |
|---|---|---|
| C1 · Presentation | Hunt / AR / Album screens | Rendering only. No distance math, no sensor access. |
| C2 · Game State | HuntSessionController | The single source of truth for "which mascot am I hunting and how hot am I". Owns the band state machine and every cooldown. |
| C3 · Sensors | LocationService | Adaptive sampling (§5.4). Emits fixes with accuracy; drops fixes worse than the accuracy gate. |
| C3 · Sensors | HeadingService | Fused true heading (magnetometer + gyro), declination-corrected, with a calibration-quality signal. |
| C3 · Sensors | GeofenceService | Registers/rotates OS geofences for the next K spawns; fires local notifications on ENTER even when the app is terminated. |
| C3 · Sensors | MotionService | Activity/speed detection — suppresses AR and capture above a speed threshold (safety, §10). |
| C4 · AR | ARSessionController | Session lifecycle, plane detection config, tracking-state reporting, anchor creation and Y resolution (§5.5), frame budget. |
| C5 · Data | Manifest cache / outbox / asset cache | Offline-first storage. The outbox replays queued captures with their **original** timestamp and fix. |

---

## 4. System Workflow & Data Flow

There are three distinct flows. Only the first and third touch the network.

### Figure 3 — Flow A: route start → spawn manifest

```
1. Route generated (route module returns route_id + ordered stops)
                    │
                    ▼
2. Client: POST /v1/routes/:routeId/mascots/generate
                    │
                    ▼
3. Orchestrator: for each route_stop →
       load ar_content for POI  ──────────►  AR Content Repo (spawn_zone polygon)
       if none: POI is skipped, no mascot   (a route may be partially AR-enabled)
                    │
                    ▼
4. Spawn Point Generator: seed = HMAC(server_secret, route_id ‖ poi_id ‖ spawn_epoch)
       rejection-sample a point inside spawn_zone  ──────►  PostGIS ST_Contains
       ≤ 30 attempts, else fallback (§5.1)
                    │
                    ▼
5. Persist mascot_spawns rows (immutable)  ──────►  Mascot Spawn Repo
                    │
                    ▼
6. Assemble manifest: [{spawnId, poiId, lat, lng, radii, mascot{modelUrl, checksum,
   scaleMeters}, bandThresholds}]   ──────►  Cache Adapter (TTL = route lifetime)
                    │
                    ▼
7. Client stores manifest + prefetches 3D assets over Wi-Fi   ──────►  C5 cache
                    │
                    ▼
8. Client registers geofences for the next K spawns            ──────►  C3 GeofenceService
```

The manifest is fetched **once per route**. From this point the hunt is fully offline-capable.

### Figure 4 — Flow B: the hunt loop (100% on-device)

```
        GPS fix (adaptive rate)
                │
                ▼
   accuracy ≤ gate?  ──no──►  drop fix, keep last band
                │yes
                ▼
   d = haversine(fix, activeSpawn)          ← §5.2
                │
                ▼
   band = classify(d, thresholds, prevBand) ← §5.3, hysteresis + 2-fix debounce
                │
        ┌───────┴────────┐
        ▼                ▼
  band changed?     band == BURNING?
        │                │
        ▼                ▼
  haptic + audio    unlock "Open camera" CTA
  + UI update       + request capture token (if online; else offline token, §5.7)
        │
        ▼
  foreground: in-app feedback only
  background/terminated: OS geofence ENTER → local notification (§5.6)
```

### Figure 5 — Flow C: AR capture

```
1. User taps "Open camera" (only enabled in BURNING)
                │
                ▼
2. ARSessionController.start()  →  horizontal plane detection ON
                │
                ▼
3. Compute placement:  ENU offset → bearing θ  →  AR yaw (θ − H₀)   ← §5.5
   XZ = fixed presentation distance (default 4 m) along that yaw
                │
                ▼
4. Resolve Y  ────────────────────────────────────────────────────┐
   a) raycast down from (X, camY, Z) onto detected planes         │
   b) no plane after 8 s → estimated ground: camY − deviceHeight  │  ← the
   c) attach ARAnchor at (X, Y, Z); ARCore/ARKit absorbs drift    │    ladder
   d) better plane later → lerp Y over 300 ms, never pop          │
                └─────────────────────────────────────────────────┘
                │
                ▼
5. Mascot rendered: yaw-billboarded, constant world scale, idle anim
                │
                ▼
6. User aligns reticle + holds 1.5 s  →  local capture success animation
                │
                ▼
7. POST /v1/mascots/:spawnId/capture  { captureToken, fix, accuracy,
   clientTs, arTelemetry, nonce }                    ← queued in outbox if offline
                │
                ▼
8. Capture Validator → Collection Service → progress_events row (checkpoint satisfied)
                │
                ▼
9. Response: { outcome, reward, isFirstCatch, collection }
```

### Latency & performance budgets

| Path | Target | Ceiling |
|---|---|---|
| Spawn manifest generation (N ≈ 8 POIs, cold) | 400 ms | 900 ms |
| Spawn manifest (cache hit) | 80 ms | 200 ms |
| Capture validation round-trip | 250 ms | 600 ms |
| On-device band recompute per fix | < 1 ms | — |
| AR session cold start → first plane | 3 s | 8 s (then fallback rung) |
| AR render | 30 fps sustained | never below 24 fps |
| Battery, hunt mode, screen off | ≤ 5 %/hour | 8 %/hour |
| Battery, AR camera active | ≤ 20 %/hour | — (session capped at 5 min, §10) |

The server budgets are dominated by PostGIS rejection sampling and are met trivially at N ≈ 8; the interesting budgets on this feature are the **battery** and **frame** budgets, which is why the hunt loop never touches the network.

---

## 5. Core Algorithms & AR Logic

### 5.1 Spawn point generation

A mascot must land somewhere a tourist can physically and safely stand. A naive "random point within R metres of the POI" puts mascots in the sea, inside buildings, and — the real hazard — in traffic lanes.

**Spawn zones are authored, not computed at runtime.** For each AR-enabled POI, a `spawn_zone GEOGRAPHY(POLYGON)` is produced once by a seeding job and reviewed by hand before the POI reaches `published`, exactly as the route spec requires of POI data itself:

1. Request a 3-minute **pedestrian isochrone** around the POI via the existing Routing Provider Adapter (cached — this is the same isochrone cache the route module already warms).
2. Subtract building footprints, water, and any way tagged `highway=motorway|trunk|primary|secondary` buffered by 8 m, pulled from the one-time Overpass extract.
3. Clip to a max radius (`spawn_radius_meters`, default 60 m) so the mascot stays associated with its POI.
4. Human review in the admin tool. The polygon is stored; the isochrone call never happens again.

**Runtime selection** is then cheap and safe:

```ts
function generateSpawnPoint(zone: Polygon, seed: Buffer): Coordinate {
  const rng = seededPrng(seed);                    // xoshiro128** — deterministic
  const bbox = boundingBox(zone);
  for (let i = 0; i < 30; i++) {
    const p = { lat: lerp(bbox.minLat, bbox.maxLat, rng()),
                lng: lerp(bbox.minLng, bbox.maxLng, rng()) };
    if (stContains(zone, p)) return p;             // PostGIS ST_Contains
  }
  return centroidOffset(zone, 10 /* m */, rng());  // fallback: near-centroid
}
```

`seed = HMAC-SHA256(SERVER_SECRET, route_id ‖ poi_id ‖ spawn_epoch)`. Determinism buys three things: the same user reopening the app gets the same spawn without a DB read; the spawn is reproducible for debugging a support report; and the seed is unguessable by a client, so spawn points cannot be predicted before the manifest is issued. The resulting point is still **persisted**, because the zone polygon may be edited later and history must survive that.

`spawn_epoch` is a coarse time bucket (default: route generation day). Rotating it is how mascots "respawn" for a repeat visitor without any new logic.

### 5.2 Distance and bearing

Distances involved are under a few hundred metres, so the equirectangular approximation is exact enough (< 0.1 % error at this range) and is ~4× cheaper than haversine — which matters when it runs on every fix on a mid-range phone. Haversine is used server-side where cost is irrelevant.

```
R  = 6_371_000                       // mean Earth radius, metres
φu, λu = user latitude/longitude in radians
φm, λm = mascot latitude/longitude in radians

dN = R · (φm − φu)                   // metres north
dE = R · (λm − λu) · cos(φu)         // metres east

d  = √(dE² + dN²)                    // ground distance, metres
θ  = atan2(dE, dN)                   // true bearing, radians clockwise from north
```

`dE`, `dN`, and `θ` are reused unchanged by the AR placement step (§5.5) — the hunt loop and the AR loop share one piece of math.

### 5.3 Proximity bands and hysteresis

| Band | Distance (default, metres) | Feedback |
|---|---|---|
| `FROZEN` | d > 300 | Direction arrow only, no haptics |
| `COLD` | 150 < d ≤ 300 | Slow pulse (1.2 s), cool UI palette |
| `WARM` | 60 < d ≤ 150 | Medium pulse (0.8 s) |
| `HOT` | 25 < d ≤ 60 | Fast pulse (0.4 s), **background notification fires here** |
| `BURNING` | d ≤ 25 | Continuous shimmer (0.12 s), **camera unlocked** |

Thresholds are per-POI overridable (`ar_contents.band_thresholds JSONB`) — a mascot in a wide-open esplanade needs different numbers than one in a tight medina alley, and the route spec already establishes per-POI checkpoint radii for the same reason.

The naive classifier flaps: a user standing still at 60 m with 8 m GPS noise will oscillate `WARM`/`HOT` several times a minute, buzzing continuously and firing repeat notifications. Two guards:

```ts
function classify(d: number, t: Thresholds, prev: Band, accuracy: number): Band {
  const margin = Math.max(8, 0.15 * boundaryOf(prev, t));   // 15 % or 8 m
  const raw = rawBand(d, t);
  // Moving to a colder band requires clearing the boundary by `margin`.
  // Moving to a hotter band is immediate — false hope is cheaper than false despair.
  if (isColder(raw, prev) && d < boundaryOf(prev, t) + margin) return prev;
  return raw;
}
```

and, in `HuntSessionController`, a **2-consecutive-fix debounce**: a new band must be produced by two successive accepted fixes before it is committed to the UI or the notification pipeline. Combined, these cut band-change events by roughly an order of magnitude in a stationary-with-drift scenario.

Accuracy handling is asymmetric on purpose:
- **Display / feedback** uses `d` directly.
- **Capture eligibility** uses `d_lower = max(0, d − min(accuracy, 20))`, so a user with a poor-but-honest fix is not locked out.
- **Server validation** uses `d_upper = d + min(accuracy, 35)`, so a spoofer cannot claim unlimited slack. Fixes with `accuracy > 50 m` are rejected outright with a "wait for better GPS" message rather than silently mis-scoring.

### 5.4 Adaptive location sampling

Continuous high-rate GPS is the single largest battery cost in this feature. Sampling rate is a function of the current band:

| Band | Distance filter | Min interval | Accuracy profile |
|---|---|---|---|
| `FROZEN` | 100 m | 60 s | Balanced (network/fused) |
| `COLD` | 40 m | 30 s | Balanced |
| `WARM` | 15 m | 10 s | High |
| `HOT` | 5 m | 3 s | High (GPS) |
| `BURNING` | 2 m | 1 s | High (GPS) |

Background mode drops one rung colder than foreground across the board. The distance filter — not the timer — does most of the work: a stationary user generates almost no fixes.

### 5.5 Geographic → AR world transform, and the ground-plane ladder

This is the core of the feature and the part most likely to be built wrong.

**Two coordinate systems.**

- *Geographic*: WGS84, from the server. Two degrees of freedom that matter (lat, lng). No usable altitude — GPS vertical error is 2–3× horizontal error, and the server has no idea what the terrain or the pavement height is at that point anyway.
- *AR world*: metric, right-handed, **Y-up and gravity-aligned**, origin at the device pose when the session started, with −Z along the initial camera forward. Both ARCore and ARKit guarantee the gravity alignment; neither guarantees any relationship to true north without a VPS service we cannot use.

**Horizontal placement (server-derived).** At session start, capture the fused true heading `H₀` (radians clockwise from north). For a mascot at bearing `θ`:

```
yaw   = θ − H₀
x_ar  =  D · sin(yaw)
z_ar  = −D · cos(yaw)
```

`D` is the **presentation distance**, not the geographic distance. Default 4 m, clamped to `[2.5 m, 6 m]`.

This substitution is the design decision worth defending to a jury. Using the true geographic distance would mean rendering a 0.6 m mascot 22 m away — sub-pixel, occluded by every real object between, and mispositioned by more than its own size given ±10 m GPS error. Using a fixed 4 m gives a mascot that is visible, that the user must physically turn to find (because `yaw` is real), and whose apparent position is wrong by an amount no one can perceive. The hunt is geographic; the reveal is theatrical. Only the bearing survives the transition, and the bearing is the only quantity that was ever reliable at that range.

Heading error consequence: at D = 4 m, a 15° compass error displaces the mascot 1.05 m laterally — about one step. Acceptable. If `HeadingService` reports low calibration quality, the UI shows the standard figure-8 calibration prompt before the session starts.

**Vertical placement (device-derived).** `y_ar` is *never* sent by the server. It is resolved through a four-rung ladder, in order:

```
Rung 1 — PLANE_HIT (preferred)
  Enable horizontal plane detection (upward-facing).
  Each frame until anchored:
    hits = session.raycast(origin: (x_ar, camY, z_ar), direction: (0,−1,0))
    plane = largest hit with area ≥ 0.5 m² and confidence ≥ threshold
    if plane: y_ar = plane.hitY ; anchor = plane.createAnchor(pose) ; DONE

Rung 2 — PLANE_ESTIMATED (after 8 s of coaching with no qualifying plane)
  y_ar = camY − deviceHeight        // deviceHeight default 1.40 m
  anchor = session.createAnchor(worldPose)   // free-floating world anchor
  Mark placement quality = ESTIMATED (telemetry).

Rung 3 — GYRO_OVERLAY (no ARCore/ARKit on device)
  No world tracking. Mascot drawn in screen space over the camera preview at
  screen position derived from (yaw − currentHeading, fixed downward pitch).
  Ground contact is faked with a soft shadow decal. Capture still valid.

Rung 4 — MAP_CAPTURE (camera denied, or ARCore unavailable and user opts out)
  Non-AR capture: hold position inside the capture radius for 10 s.
  Same server validation, same reward, no camera.
```

Refinement after anchoring: the raycast continues at 2 Hz for 5 s. If a qualifying plane appears whose `hitY` differs from the current `y_ar` by more than 5 cm, `y_ar` is **lerped** to the new value over 300 ms and the anchor is re-parented to the plane. Snapping instantly is the classic AR bug where the character jumps a metre mid-animation.

Once anchored, `y_ar` is frozen and the mascot is parented to the `ARAnchor`. From that moment ARCore/ARKit's own drift correction moves the mascot with the world — the app does no per-frame position math at all, which is what keeps the frame budget.

Two rendering rules that depend on this:
- **Yaw-only billboarding.** The mascot rotates to face the camera about Y only. Full billboarding tilts the character off the floor and destroys the illusion the whole ladder exists to create.
- **Constant world scale.** `scale_meters` from the catalog (default 0.6 m tall). It must shrink as the user backs away, or it reads as a sticker rather than an object.

**Coaching UI** runs during rung 1: "Point your phone at the ground and move slowly." Plane detection needs parallax and texture; without an explicit instruction users hold the phone still at chest height and detection never converges. This one overlay is worth more to the success rate than any tuning parameter in this document.

### 5.6 Background and terminated-app alerting

The requirement — notify when the user is *hot* while the app is closed — is where the two platforms diverge sharply, and where a naive "run a background timer" approach fails on iOS.

**The mechanism is OS geofencing, not background polling.** Both platforms wake a terminated app for a geofence transition; neither reliably runs an arbitrary background loop.

| | Android | iOS |
|---|---|---|
| API | `GeofencingClient` (Play Services) or foreground service + `LocationCallback` | Core Location `CLCircularRegion` monitoring |
| Regions per app | 100 | **20** |
| Wakes terminated app | Yes (broadcast receiver) | Yes (`didEnterRegion`, ~10 s of runtime) |
| Min practical radius | ~100 m | ~100 m |

Because iOS caps at 20 regions **for the entire app**, geofences are **rotated, not bulk-registered**. `GeofenceService` maintains regions only for the next `K` un-captured spawns along the route (`K = 5` on iOS, `K = 20` on Android), re-computing the set on every capture and on every significant location change. A route with 12 mascots therefore never exceeds the budget.

Two regions are registered per spawn:
- **HOT region**, radius = `hot_radius` (default 60 m) → fires the local notification.
- **BURNING region**, radius = `capture_radius` (default 25 m) → upgrades the notification to "Tap to open the camera" and pre-warms the AR asset.

The minimum practical geofence radius on both platforms is around 100 m, larger than our HOT band. The `capture_radius` region is therefore registered at 100 m and **the exact distance is re-verified in the wake handler** against a fresh single fix before anything is shown. The geofence is a cheap wake-up trigger; it is never the authority on the band.

Notification policy, enforced client-side in `HuntSessionController` and mirrored server-side in `Notification Policy` for any push:
- Max **1 notification per spawn per 15 minutes**.
- Max **6 hunt notifications per day**.
- Quiet hours 22:00–07:00 local, user-configurable, hard-suppressed.
- Suppressed entirely while the app is in the foreground (the UI is already saying it).
- Suppressed while `MotionService` reports vehicle-speed motion.

**FCM push is deliberately not the mechanism for proximity alerts.** It requires connectivity, adds a server round-trip, and would require the server to know the user's live position — which means streaming GPS to the backend, with the battery, data, and privacy cost that implies. Push is reserved for genuinely server-originated events: an admin publishing a new mascot on a route in progress, or a manifest invalidation. `Push Adapter` and the `push_tokens` table exist for those, not for the hunt.

### 5.7 Capture validation and anti-cheat

The client is untrusted. It knows the spawn coordinate (it must, to compute distance offline), so a modified client can trivially claim to be standing on it. The design accepts this and aims at *proportionate* deterrence — this is a tourism stamp rally, not a competitive economy.

**Capture token.** When the client first enters `BURNING` and is online, it calls `POST /v1/mascots/:spawnId/proximity` with its fix. The server verifies the distance and returns a **short-lived HMAC-signed token** (TTL 5 min) bound to `spawnId ‖ user/session ‖ issued_at ‖ fix_geohash`. The capture request must present it. This forces at least one verified proximity claim at a real timestamp and prevents a captured-anywhere replay of the capture endpoint.

If offline at that moment, the client mints a local **offline claim** and queues the capture; the server accepts an offline claim only when the outbox replay arrives within 24 h and every other check passes (§10).

**Validator checks, in order** (first failure short-circuits, all attempts are logged):

```ts
CaptureValidator.validate(req): CaptureOutcome
  1. spawn exists, belongs to req.routeId, state = 'active'         → else NOT_FOUND
  2. idempotency: client_nonce unseen                                → else return prior result
  3. not already captured by this user/session                       → else ALREADY_CAPTURED
  4. accuracy ≤ 50 m                                                 → else LOW_ACCURACY (retryable)
  5. d_upper = distance(req.fix, spawn.location) + min(accuracy,35)
     d_upper ≤ capture_radius                                        → else TOO_FAR
  6. captureToken valid, unexpired, geohash within 150 m of req.fix  → else INVALID_TOKEN
  7. clientTs within ±5 min of serverTs (or ≤24 h for offline replay)→ else STALE
  8. implied speed from previous accepted capture ≤ 120 km/h         → else IMPLAUSIBLE (flagged, not blocked)
  9. per-user capture rate ≤ 20/hour                                 → else RATE_LIMITED
```

Check 8 is flagged rather than blocked on purpose: a legitimate user on a fast road between two distant clusters shouldn't be punished for the route module's own hybrid driving design. Flags accumulate in `mascot_captures.flags` for offline review — the correct place to catch cheating in a competition demo is a report, not a runtime block that could embarrass a live jury walkthrough.

Not implemented, and stated so honestly: mock-location detection (`isFromMockProvider` is trivially bypassed and unavailable on iOS), device attestation (Play Integrity / DeviceCheck — free, but a meaningful integration cost), and server-side proof-of-camera. These are listed in §9 as post-competition hardening.

**No camera imagery is ever transmitted.** The capture payload contains coordinates and AR telemetry counters only. This is both a bandwidth decision and a privacy one, and it means the feature has no image-processing attack surface.

---

## 6. APIs & External Services

| Service | Role | Notes |
|---|---|---|
| **ARCore** (`com.google.ar:core`) | Android plane detection, motion tracking, anchors | Free, no card, no cloud project. Device-support list is a real constraint → rung 3/4 fallbacks. |
| **ARKit** (RealityKit) | iOS plane detection, motion tracking, anchors | Free. iOS 13+, A9 chip or later. |
| **ARCore Geospatial API** | *Rejected* | Requires Google Cloud billing (card) and Street View–derived VPS coverage, which is effectively absent for Algerian cities. Compass-based heading is used instead (§5.5). |
| **Firebase Cloud Messaging** | Server-originated push only | Free tier, no card required for FCM itself. Not used for proximity alerts. |
| **GraphHopper / ORS** | Pedestrian isochrones for spawn-zone authoring | **Already integrated** by the route module. Build-time only, cached; adds no runtime quota pressure. |
| **Overpass API** | Building/water/highway geometry for spawn-zone subtraction | Already in use for POI bootstrap. One-time pull per city. |
| **Asset hosting** | `.glb` / `.usdz` model delivery | Served as static files by the existing Node service behind nginx caching, with SHA-256 checksums and signed URLs. Avoids any card-gated CDN. Total asset footprint at 12 mascots ≈ 40 MB. |
| **8th Wall / WebXR AR** | *Rejected for web* | 8th Wall is paid; WebXR immersive-AR is unsupported on iOS Safari. Web app is non-capture (§8). |

### Flutter package selection

| Need | Package | Note |
|---|---|---|
| Location | `geolocator` | Foreground service config on Android; accuracy profiles. |
| Geofencing | `native_geofence` (or a thin platform channel) | Must survive app termination — verify this property before committing. |
| Heading | `flutter_compass` + declination table | Fuse with gyro for stability. |
| Local notifications | `flutter_local_notifications` | Fired from the geofence wake handler. |
| Haptics | `Haptic Feedback` / `vibration` | Pattern-based pulse. |
| AR | **Thin platform channel over ARCore + ARKit** | See below. |
| Push | `firebase_messaging` | Server-originated events only. |
| Local DB | `drift` or `isar` | Manifest cache + outbox. |

**On the AR plugin — the highest-risk dependency in this module.** The Flutter AR plugin ecosystem is thin and intermittently maintained; no package currently exposes the specific combination this design needs (raycast against a *specific* world point rather than a screen tap, plane-area/confidence filtering, and anchor re-parenting). The specification is therefore for a **purpose-built thin platform channel**: a Kotlin surface over ARCore + Filament and a Swift surface over RealityKit, exposing exactly six methods —

```dart
abstract class ArBridge {
  Future<ArCapability> checkCapability();               // FULL | LIMITED | NONE
  Future<void> startSession({required bool planeDetection});
  Stream<TrackingState> trackingState();                // + planeCount, quality
  Future<double?> raycastGroundY(double x, double z);   // null = no plane yet
  Future<String> placeAnchor(Vector3 pos, String modelUri, double scaleMeters);
  Future<void> endSession();
}
```

Everything above this line is Dart and is testable with a fake `ArBridge`. Roughly 400 lines of platform code, versus fighting an abandoned plugin's abstractions — and it makes rung 3 and rung 4 trivial to implement, because they simply don't call the bridge.

### HTTP surface (Layer 1)

```
POST   /v1/routes/:routeId/mascots/generate   → 201 SpawnManifest
GET    /v1/routes/:routeId/mascots            → 200 SpawnManifest (cached, ETag)
POST   /v1/mascots/:spawnId/proximity         → 200 { captureToken, expiresAt }
POST   /v1/mascots/:spawnId/capture           → 200 CaptureResult   (Idempotency-Key required)
POST   /v1/mascots/captures/batch             → 200 CaptureResult[] (offline outbox replay)
GET    /v1/collection                         → 200 CollectionAlbum
GET    /v1/mascots/:mascotId/asset            → 302 signed URL + X-Asset-Checksum
POST   /v1/devices/push-token                 → 204

# Admin
POST   /v1/admin/pois/:poiId/ar-content       → 201 ArContent
PUT    /v1/admin/ar-contents/:id/spawn-zone   → 200 (GeoJSON polygon)
GET    /v1/admin/captures?flagged=true        → 200 CaptureAudit[]
```

### 3D asset budget

| Constraint | Value |
|---|---|
| Format | `.glb` (Draco-compressed) for Android/web, `.usdz` for iOS — both exported from one source |
| Triangles | ≤ 30 000 |
| Textures | one 1024² atlas, KTX2/Basis where supported |
| File size | ≤ 3 MB per mascot per format |
| Animations | ≤ 3 clips (idle, react, capture), ≤ 40 bones |
| World height | 0.4–0.9 m (`scale_meters`) |

---

## 7. Data Models & Key Interfaces

### Schema (PostgreSQL / PostGIS)

```sql
-- MASCOTS — species catalog, city-agnostic
CREATE TYPE mascot_rarity AS ENUM ('common', 'uncommon', 'rare', 'legendary');

CREATE TABLE mascots (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key             TEXT NOT NULL UNIQUE,          -- 'fennec', 'corsair-cat'
  name_fr         TEXT NOT NULL,
  name_ar         TEXT NOT NULL,
  name_en         TEXT NOT NULL,
  lore_fr         TEXT, lore_ar TEXT, lore_en TEXT,
  rarity          mascot_rarity NOT NULL DEFAULT 'common',
  model_glb_ref   TEXT NOT NULL,                 -- storage key, Android/web
  model_usdz_ref  TEXT NOT NULL,                 -- storage key, iOS
  model_checksum  TEXT NOT NULL,                 -- SHA-256, client cache validation
  scale_meters    NUMERIC(4,2) NOT NULL DEFAULT 0.60,
  thumbnail_ref   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- AR_CONTENTS — per-POI AR configuration. This is the table the route spec
-- reserved with `pois.ar_content_id UUID -- FK added once AR module owns its table`.
CREATE TABLE ar_contents (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poi_id                UUID NOT NULL REFERENCES pois(id),
  mascot_id             UUID NOT NULL REFERENCES mascots(id),
  spawn_zone            GEOGRAPHY(POLYGON, 4326) NOT NULL,  -- curated, §5.1
  spawn_radius_meters   INT  NOT NULL DEFAULT 60,           -- zone clip radius
  capture_radius_meters INT  NOT NULL DEFAULT 25,           -- BURNING boundary
  hot_radius_meters     INT  NOT NULL DEFAULT 60,           -- HOT boundary / geofence
  band_thresholds       JSONB NOT NULL DEFAULT '{}',        -- per-POI overrides
  presentation_distance_meters NUMERIC(3,1) NOT NULL DEFAULT 4.0,
  is_enabled            BOOLEAN NOT NULL DEFAULT true,
  zone_reviewed_by      TEXT,                               -- manual safety review
  zone_reviewed_at      TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (poi_id)
);
CREATE INDEX idx_ar_contents_zone ON ar_contents USING GIST (spawn_zone);

-- Close the loop left open in the route spec:
ALTER TABLE pois
  ADD CONSTRAINT fk_pois_ar_content
  FOREIGN KEY (ar_content_id) REFERENCES ar_contents(id);

-- MASCOT_SPAWNS — one instance per (route, POI). Immutable, like `routes`.
CREATE TYPE spawn_state AS ENUM ('active', 'captured', 'expired');

CREATE TABLE mascot_spawns (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  route_id        UUID NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
  poi_id          UUID NOT NULL REFERENCES pois(id),
  ar_content_id   UUID NOT NULL REFERENCES ar_contents(id),
  mascot_id       UUID NOT NULL REFERENCES mascots(id),
  location        GEOGRAPHY(POINT, 4326) NOT NULL,   -- horizontal only, no altitude
  spawn_seed      TEXT NOT NULL,                     -- reproducibility / audit
  spawn_epoch     DATE NOT NULL,
  state           spawn_state NOT NULL DEFAULT 'active',
  expires_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (route_id, poi_id)
);
CREATE INDEX idx_mascot_spawns_route ON mascot_spawns (route_id) WHERE state = 'active';
CREATE INDEX idx_mascot_spawns_location ON mascot_spawns USING GIST (location);

-- MASCOT_CAPTURES — append-only, records rejected attempts too (audit trail)
CREATE TYPE capture_outcome AS ENUM (
  'accepted', 'too_far', 'low_accuracy', 'already_captured',
  'invalid_token', 'stale', 'rate_limited'
);
CREATE TYPE placement_quality AS ENUM (
  'plane_hit', 'plane_estimated', 'gyro_overlay', 'map_capture'
);

CREATE TABLE mascot_captures (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  spawn_id          UUID NOT NULL REFERENCES mascot_spawns(id) ON DELETE CASCADE,
  user_id           UUID,             -- nullable until auth exists
  session_id        UUID,             -- anonymous demo usage
  client_nonce      TEXT NOT NULL,    -- idempotency
  outcome           capture_outcome NOT NULL,
  device_fix        GEOGRAPHY(POINT, 4326),
  fix_accuracy_m    NUMERIC(6,2),
  measured_distance_m NUMERIC(8,2),
  placement         placement_quality,
  ar_telemetry      JSONB NOT NULL DEFAULT '{}',  -- planeCount, trackingState, ttfPlaneMs
  flags             TEXT[] NOT NULL DEFAULT '{}', -- 'implausible_speed', ...
  client_ts         TIMESTAMPTZ NOT NULL,
  is_offline_replay BOOLEAN NOT NULL DEFAULT false,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (client_nonce)
);
CREATE INDEX idx_captures_spawn ON mascot_captures (spawn_id);
CREATE INDEX idx_captures_flagged ON mascot_captures (created_at)
  WHERE array_length(flags, 1) > 0;
CREATE UNIQUE INDEX uq_capture_accepted_per_spawn
  ON mascot_captures (spawn_id) WHERE outcome = 'accepted';

-- COLLECTION — the album / "dex"
CREATE TABLE mascot_collection (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID,
  session_id        UUID,
  mascot_id         UUID NOT NULL REFERENCES mascots(id),
  first_captured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  capture_count     INT NOT NULL DEFAULT 1,
  UNIQUE (user_id, mascot_id),
  UNIQUE (session_id, mascot_id)
);

-- PUSH TOKENS — server-originated events only
CREATE TYPE device_platform AS ENUM ('android', 'ios', 'web');
CREATE TABLE push_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID,
  session_id    UUID,
  token         TEXT NOT NULL UNIQUE,
  platform      device_platform NOT NULL,
  ar_capability TEXT,                     -- 'full' | 'limited' | 'none' — telemetry
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

An accepted capture also writes a `progress_events` row (the route module's existing table) for the corresponding POI — **capture implies checkpoint arrival**, so the two modules never disagree about whether a stop was visited.

### Adapter and Domain interface contracts

```ts
// ---------- Adapter layer ----------
interface PushAdapter {
  send(tokens: string[], payload: PushPayload): Promise<void>   // never throws upward
}

interface AssetStoreAdapter {
  getSignedUrl(storageKey: string, ttlSeconds: number): string
  getChecksum(storageKey: string): string
}

// RoutingProviderAdapter and CacheAdapter are reused unchanged from the route module.

// ---------- Domain layer — pure, no DB or provider access ----------
SpawnPointGenerator.generate(
  zone: Polygon,
  seed: Buffer
): Coordinate

ProximityBandCalculator.classify(
  distanceMeters: number,
  thresholds: BandThresholds,
  previousBand: Band,
  accuracyMeters: number
): Band
// ^ mirrored byte-for-byte in Dart; parity enforced by shared fixture (§11)

CaptureValidator.validate(
  spawn: MascotSpawn,
  request: CaptureRequest,
  history: CaptureHistory,
  now: Date
): { outcome: CaptureOutcome; flags: string[] }

NotificationPolicy.shouldNotify(
  spawnId: string,
  recent: NotificationLog,
  localTime: Date,
  userPrefs: NotificationPrefs
): boolean

CollectionService.applyCapture(
  capture: AcceptedCapture,
  existing: CollectionEntry | null
): { entry: CollectionEntry; isFirstCatch: boolean; reward: Reward }
```

### Client contracts (Dart)

```dart
// C2 — the only object that knows the hunt state
class HuntSessionController {
  Stream<HuntState> get state;          // band, distance, bearing, canCapture
  void onFix(Position fix);             // from C3
  Future<CaptureResult> attemptCapture(ArTelemetry telemetry);
  void onGeofenceEnter(String spawnId, GeofenceKind kind);   // wake handler
}

// C4 — see §6 for ArBridge
class MascotPlacement {
  final double yawRadians;              // θ − H₀
  final double presentationDistance;    // metres, from manifest
  double? groundY;                      // null until a rung resolves it
  PlacementQuality quality;
}
```

---

## 8. Feature Specifications

| Feature | Description |
|---|---|
| **Hidden mascot per POI** | One seeded, walkable, safety-reviewed spawn point per AR-enabled POI on the route. Position not revealed on the map — only the hot/cold signal and a direction arrow. |
| **Hot/cold proximity hunt** | Five bands with hysteresis and debounce; haptic pulse rate, audio cue interval, and UI temperature all derived from the same band. Fully on-device and offline. |
| **Background & terminated alerts** | OS geofences on the next K spawns fire local notifications on entering HOT and BURNING, with distance re-verified in the wake handler. Cooldowns, daily cap, quiet hours. |
| **Floor-locked AR placement** | Horizontal position from the server; vertical resolved on-device via plane raycast, with a four-rung degradation ladder ending in a camera-free capture mode. |
| **Camera capture** | Reticle-over-mascot hold for 1.5 s. Local success animation first, server confirmation second — the interaction never waits on the network. |
| **Server-validated captures** | Capture token, distance and accuracy gates, idempotency, plausibility flags, full audit trail of accepted and rejected attempts. |
| **Offline capture queue** | Outbox pattern. Captures made without connectivity replay with their original fix and timestamp, re-validated within a 24 h window. |
| **Collection album** | Per-user/session mascot album with rarity, lore, first-catch date, and a 3D viewer. Works on web. |
| **Checkpoint integration** | An accepted capture emits the route module's `progress_events` row — one visit signal, not two competing ones. |
| **Admin spawn-zone editor** | Map polygon editor with the isochrone-minus-obstacles proposal pre-drawn, requiring explicit human sign-off (`zone_reviewed_by`) before a POI's AR content goes live. |
| **Web app role (non-capture)** | Route browsing, hunt progress, and a `<model-viewer>` 3D album. **No web capture:** WebXR immersive-AR is unavailable on iOS Safari and the paid alternatives are card-gated. Stated as a product decision, not an omission. |

---

## 9. Implementation Roadmap & Development Order

Bottom-up by dependency. Steps 2 and 3 are independent leaf branches and can run in parallel; **step 4 is sequenced early despite being client work because it carries the highest technical uncertainty in the module** — the same reasoning that put the Adapter first in the route spec.

1. **Define contracts.** `ArContent` shape, spawn manifest JSON, `ArBridge` method signatures, band threshold schema, capture request/response. Design only, no code. Freeze the manifest shape first — both teams build against it.
2. **Data layer.** Schema above, plus the `pois.ar_content_id` FK. Seed 3 mascots and 5 hand-authored `ar_contents` with polygons drawn by hand in geojson.io over the pilot-city fixture POIs. No isochrone tooling yet.
3. **Domain layer, server.** In dependency order: `ProximityBandCalculator` and `SpawnPointGenerator` first (pure), then `CaptureValidator`, then `CollectionService`, then `NotificationPolicy`. Unit test each before the next.
4. **AR spike — `ArBridge` on Android only.** Hardcode one model at a fixed 4 m in front of the camera and resolve Y by plane raycast. **The single most important checkpoint in this plan:** if plane detection does not converge reliably in 3–5 s on real pavement in the pilot city, rungs 2–4 become the primary design and the schedule is re-planned around it. Do this before writing any UI.
5. **Orchestration + Layer 1.** Wire manifest generation and the capture pipeline; expose the endpoints. Driver script → controller, same pattern as the route module.
6. **Client sensors (C3) + hunt loop (C2).** Location sampling, heading, band state machine, haptics. Testable with a mocked manifest and a simulated GPS track — **build a route-replay harness here**; walking outside to test every change will otherwise dominate the schedule.
7. **AR screen (C4/C1).** Full placement ladder, coaching UI, capture interaction, asset caching.
8. **Geofencing and notifications.** Region rotation, wake handler, re-verification, cooldowns. Test with terminated app on both platforms — this is where platform surprises live.
9. **Offline outbox + collection album.** Queue, replay, batch endpoint, album UI on mobile and web.
10. **Admin spawn-zone tooling + isochrone proposal job.** Only now, once the runtime consumes zones correctly.
11. **Field test in the pilot city.** Full route walked end-to-end by 3+ people on 3+ device tiers. Tune `band_thresholds`, `presentation_distance`, and hysteresis margins from real telemetry — every default in this document is a starting guess.
12. *(Post-competition)* Device attestation, mock-location heuristics, timed/seasonal spawns, shared spawns between users.

---

## 10. Edge Cases & Assumptions

### Positioning & sensors

- **GPS drift in dense old-city areas** (already flagged in the route spec) directly attacks the band signal. Mitigated by hysteresis, the 2-fix debounce, the accuracy gate, and asymmetric accuracy slack (§5.3). It is not eliminated, and the `capture_radius` default of 25 m is deliberately generous because of it.
- **Compass error** near vehicles, rebar, and metal railings can reach 30°+. At the 4 m presentation distance this displaces the mascot ~2 m — the user turns slightly further and still finds it. The calibration prompt fires when quality is reported low. This tolerance is the whole reason for the fixed presentation distance.
- **Indoor POIs** (museums, mosque interiors) have no usable GPS. Such POIs should be marked `is_enabled = false` on their `ar_contents` for v1; the route still includes them, they simply have no mascot. Indoor anchoring is a v2 problem requiring markers or Cloud Anchors.
- **Altitude is never used.** Neither from GPS nor from the server. A mascot at the top of a staircase and one at the bottom are the same point to this system. Accepted for v1; POIs with severe vertical separation should have tight spawn zones.

### AR & devices

- **Plane detection fails** on uniform paving, wet ground, sand, low light, and any textureless surface. Rung 2 exists precisely for this and is expected to be used in a meaningful minority of sessions — it is a designed path, not an error state, and it is tracked in `placement` telemetry so the real ratio is measurable.
- **Device without ARCore.** A real and non-trivial share of the target device population. Rung 3 (gyro overlay) keeps the feature playable; `checkCapability()` is called at app start, not at camera open, so the UI never promises AR it cannot deliver.
- **Camera permission denied.** Rung 4 (map capture) yields identical rewards. No content is gated behind granting camera access.
- **Thermal throttling.** Continuous AR heats mid-range phones and degrades tracking. AR sessions are capped at 5 minutes, then prompt to resume; the session ends on capture regardless.

### Safety

- **No mascot on a roadway.** Enforced structurally (spawn zones subtract buffered major highways) and procedurally (`zone_reviewed_by` sign-off before publish). This is the single check that must not be skipped for a demo deadline.
- **Movement suppression.** Capture and AR are disabled above a vehicle-speed threshold from `MotionService`.
- **Attention warning.** A one-time-per-session overlay before the first AR launch: stay aware of your surroundings, watch for traffic. Standard for the genre and cheap.
- **Quiet hours** are hard-suppressed, not merely defaulted.

### Data & operations

- **Not every POI needs a mascot.** `ar_contents` is optional per POI; a route with 10 stops and 6 AR-enabled POIs is normal and the manifest simply omits the rest.
- **Zone edits do not rewrite history.** Existing `mascot_spawns` rows keep their coordinates; the edit affects future spawns only.
- **Offline replay window** is 24 h. Beyond that a queued capture is rejected as `stale`, with a user-facing explanation. The window is a config value.
- **Anonymous sessions** can collect mascots, mirroring the route module's nullable `user_id`. Merging an anonymous collection into a real account on later signup is deferred with auth.
- **Privacy.** Camera frames never leave the device; no imagery is uploaded, stored, or processed server-side. Location is transmitted only at manifest fetch, proximity-token issuance, and capture — three points per mascot, not a continuous stream.
- **Asset delivery on mobile data.** Models are prefetched on Wi-Fi when available and are checksum-verified and LRU-cached. A cold 3 MB download on a poor connection at the moment of capture is exactly the failure the prefetch step exists to avoid.

---

## 11. Basic Testing Strategy

| Level | What & how |
|---|---|
| **Unit — pure functions (server)** | `ProximityBandCalculator` against a distance-sequence fixture including flapping scenarios; `SpawnPointGenerator` as a property test (1000 seeds × 5 zones, assert every result satisfies `ST_Contains`); `CaptureValidator` against a table of crafted requests — too far, stale, low accuracy, replayed nonce, teleport; `NotificationPolicy` cooldown/quiet-hours arithmetic. |
| **Cross-language parity** | A shared `band-fixtures.json` (distance, accuracy, previous band → expected band) is executed by **both** the TypeScript and the Dart implementations in their respective CI suites. Server and client disagreeing about what "hot" means is the most likely silent bug in this module; this test is what prevents it. |
| **Repository** | `ar_contents` polygon storage/retrieval round-trip, spawn uniqueness per `(route_id, poi_id)`, the partial unique index that permits only one accepted capture per spawn. Against the same 5–10 fixture POIs the route module uses. |
| **Adapter** | `PushAdapter` and `AssetStoreAdapter` mocked in all automated runs. The Routing Provider Adapter is untouched here — the AR module only uses it in the offline zone-authoring job, so no free-tier quota is consumed by the test suite. |
| **Client — hunt loop** | `HuntSessionController` driven by a **replayable GPS track fixture** (a recorded or synthetic walk toward a spawn, with injected noise and accuracy degradation). Asserts band sequence, notification count, and that cooldowns hold. Runs headless in CI — no walking required. |
| **Client — AR** | `ArBridge` faked. Asserts the ladder: plane returned → `plane_hit`; no plane for 8 s → `plane_estimated`; capability `NONE` → `gyro_overlay`; permission denied → `map_capture`. Asserts Y is lerped, never snapped, on late plane discovery. |
| **Integration** | Manifest generation → hunt simulation → capture → collection updated → `progress_events` row written, run end-to-end against the fixture city. |
| **Device matrix (manual)** | Minimum three tiers: a recent ARCore flagship, a mid-range ARCore device, and a non-ARCore device. Each must complete a capture via its expected rung. |
| **Field test (manual checklist)** | Per mascot: time-to-first-plane, whether the mascot was findable within 60 s, placement quality reported, background notification received with the app terminated, capture accepted on the first attempt. This checklist is the actual acceptance criterion for the module — everything above only proves the code does what it was told. |