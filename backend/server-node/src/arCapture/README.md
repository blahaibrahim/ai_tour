# AR Capture Module — skeleton

Implements the layering in `docs/mascot_plan.md` (*AR Capture Module —
Technical Design Specification v1.0*), the companion to *Route Generation
Module — Technical Design Specification v1.0* that `../routeGeneration/`
implements. Same posture as that module: the contracts, the schema and the
HTTP surface are done so the Flutter client can be developed against the real
shape now, but most of Layer 5 (Data) and Layer 4 (Adapter) are stubs.

**Unlike `routeGeneration/`, this module's Layer 3 (Domain) is mostly real.**
`proximityBandCalculator.ts`, `spawnPointGenerator.ts`, `notificationPolicy.ts`,
`collectionService.ts`, `captureValidator.ts` and `captureToken.ts` all have
working implementations, not stubs — every one of them is pure (no DB, no
provider, no HTTP), so there was nothing blocking them, and two of them
(`proximityBandCalculator.ts`, the cross-language parity requirement) had to
exist before `test/band-fixtures.json` could even be written. See each file's
own STATUS note.

## Current behaviour

`AR_CAPTURE_MODE` (env, default `fixture`):

| Value | What the endpoints do |
|---|---|
| `fixture` | Serve `fixtures.ts` — one fennec spawn on the fixture route's Ketchaoua Mosque stop, always inside BURNING range so the full hunt→capture→collection loop is exercisable end to end. Logs a loud warning at boot. |
| `real` | Call `orchestrator.ts`. Manifest generation calls into `routeGeneration` (itself likely still in `fixture` mode — see its own README) and then the AR Data layer, which throws `501 not_implemented` naming the first missing repository or adapter method. |

Flip the default in `index.ts` when the Data layer lands. No endpoint changes.

## Layout

```
arCapture/
  types.ts             Layer boundaries — plan §7 contracts, transcribed
  errors.ts             Error vocabulary; each class carries its own HTTP status
  index.ts              Module's public face + the fixture/real switch
  orchestrator.ts        Layer 2 — the call sequence, written out and wired
  fixtures.ts            Placeholder data. Delete when the Data layer works.
  domain/                Layer 3 — pure, no provider or DB access
    proximityBandCalculator.ts   spawnPointGenerator.ts   deterministicRandom.ts
    captureValidator.ts   captureToken.ts   collectionService.ts   notificationPolicy.ts
  adapters/               Layer 4
    pushAdapter.ts         Interface + FCM shell (stub)
    assetStoreAdapter.ts   Interface + signed-URL shell (stub)
    (Routing Provider + Cache adapters are REUSED from ../routeGeneration/adapters/
     unchanged — see plan §3.)
  data/                   Layer 5
    mascotRepository.ts  arContentRepository.ts  mascotSpawnRepository.ts
    captureRepository.ts  collectionRepository.ts  pushTokenRepository.ts
```

`../routes/mascots.ts` is Layer 1. `../../sql/002_ar_capture.sql` is the
schema — it extends `001_route_generation.sql`'s `pois`/`routes` tables and
cannot be applied without them.

## Build order

From the plan's own §9, adapted the same way `routeGeneration/README.md`
adapted its spec's — bottom-up by dependency, pure pieces first regardless of
which "layer" they're numbered.

1. **Contracts** — done (`types.ts`).
2. **Data** — the six repositories in `data/`, seeded with 3-5 hand-authored
   fixture spawn zones (plan §9 step 2). `ArContentRepository.upsertSpawnZone`
   is the one write path; everything else is read-only until the admin editor
   (plan §9 step 10) exists.
3. **Domain** — already done for the pure pieces (see above). What's left
   needs Data: nothing, actually — every plan-named Domain component
   (`SpawnPointGenerator`, `ProximityBandCalculator`, `CaptureValidator`,
   `CollectionService`, `NotificationPolicy`) is pure by the plan's own
   signatures (plan §7's "Adapter and Domain interface contracts"). The
   *orchestrator* is what needs Data, not the domain functions themselves.
4. **AR spike** — client-side (`ArBridge` on Android), not this module. See
   `lib/ar/` in the Flutter app.
5. **Orchestration + Layer 1** — already wired; starts working as Data lands.
6. **Geofencing, offline outbox, collection album UI, admin tooling** — plan
   §9 steps 8-10, all client-side or admin-only. Not started.

## The rules that are easy to break

- **Horizontal position is server-authoritative, vertical is device-derived**
  (plan §2, §5.5). This module never computes or stores a `y`/altitude value
  for a spawn — `mascot_spawns.location` is `GEOGRAPHY(POINT, 4326)`,
  horizontal only, on purpose.
- **`ProximityBandCalculator` must stay byte-for-byte identical to the Dart
  client's** (`lib/ar/proximity.dart`). This is the plan's own named highest
  risk ("the most likely silent bug in this module") — `test/band-fixtures.json`
  plus `test/arCaptureParity.ts` here and `test/proximity_parity_test.dart` on
  the Flutter side exist specifically to catch a drift.
- **Capture tokens are self-verifying, not looked up.** `captureToken.ts`
  signs and checks an HMAC over the token's own payload; there is no
  `capture_tokens` table anywhere in `sql/002`. Do not add one — the whole
  point of a signed token is that verifying it costs nothing.
- **No camera imagery is ever transmitted or stored** (plan §5.7). The
  capture payload and `mascot_captures.ar_telemetry` are coordinates and
  counters only — never add an image field to either.
- **`mascot_captures` is append-only.** Rejected attempts are inserted too,
  same as accepted ones — that is the anti-cheat audit trail (plan §7).

## Deviations from the plan

Marked `NOT IN SPEC` in the code wherever they appear. None are agreed —
confirm before relying on them.

| What | Where | Why |
|---|---|---|
| `/api/...` paths instead of `/v1/...` | `routes/mascots.ts` | This deployment's existing convention — every other router already uses `/api`. |
| `Idempotency-Key` is the body's `nonce`, not a header | `routes/mascots.ts` | Plan §4's own Flow C JSON body already carries `nonce`; a header would be a second name for the same value. |
| No `session_id`-based anonymous identity | `sql/002`, `types.ts` | `routeGeneration`'s own schema (`001`) already made every request authenticated via Supabase auth (including anonymous sign-in) rather than a raw session id — see `001`'s RLS note. `session_id` columns are kept in the schema for fidelity with the plan's tables but are expected to stay null. |
| Capture token's `fix_geohash` binding is a plain coordinate + distance check | `domain/captureToken.ts`, `domain/captureValidator.ts` | Answers the same "was this issued near here" question at the plan's own 150 m tolerance, without a geohash library dependency. |
| Reward point values per rarity | `domain/collectionService.ts` | Plan §7's `Reward` type has no named point table. Scaled from the client's existing 30-point task default. |
| `MascotRepository` as its own repository | `data/mascotRepository.ts` | Plan §3's Layer 5 table doesn't list one, but `ar_contents.mascot_id` / `mascot_spawns.mascot_id` both need a read path the manifest assembly step actually uses. |
| Admin endpoints not built | `routes/mascots.ts` | No admin auth surface exists anywhere in this deployment yet. |
| Manifest caching via the Cache Adapter | `index.ts` (`getManifest`) | Plan §4 step 6 calls for it; the reused `CacheAdapter` interface is specific to route matrices/isochrones today. Re-assembling per call is correct but uncached until that interface grows a generic slot. |

## Testing

Per plan §11:

| Level | What |
|---|---|
| Unit — pure functions | `test/arCaptureParity.ts` — `ProximityBandCalculator` against `test/band-fixtures.json`'s distance-sequence cases (including flapping scenarios); `SpawnPointGenerator` as a property check (many seeds × zones, every result satisfies point-in-polygon); `CaptureValidator` against crafted requests — too far, stale, low accuracy, replayed nonce; `NotificationPolicy` cooldown/quiet-hours arithmetic. Run with `npm test`. |
| **Cross-language parity** | `test/band-fixtures.json` is executed by both this module (`test/arCaptureParity.ts`) and the Flutter client (`test/proximity_parity_test.dart`). This is the test the plan calls out by name (§11) as preventing the most likely silent bug in the module. |
| Repository | Against 3-5 hand-authored fixture zones, once Data is built. Not started. |
| Adapter | `PushAdapter` and `AssetStoreAdapter` mocked in every automated run — same rule as `routeGeneration`'s Routing Provider Adapter. |
| Integration | Manifest generation → hunt simulation → capture → collection updated, against the fixture city. Not started — needs `routeGeneration` past fixture mode too. |
