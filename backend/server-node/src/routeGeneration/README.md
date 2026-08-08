# Route Generation Module — skeleton

Implements the layering in *Route Generation Module — Technical Design
Specification v1.0*. **Nothing below Layer 1 is built.** Every domain, adapter
and repository method throws `NotImplementedError` naming itself.

The endpoints, the contracts, the schema and the error vocabulary are done, so
the Flutter client can be developed against the real shape now.

## Current behaviour

`ROUTE_GENERATION_MODE` (env, default `fixture`):

| Value | What the endpoints do |
|---|---|
| `fixture` | Serve `fixtures.ts` — a real two-cluster Algiers route with drive and walk segments. Logs a loud warning at boot. |
| `real` | Call `orchestrator.ts`, which throws `501 not_implemented` naming the first missing component. |

Flip the default in `index.ts` when the orchestrator lands. No endpoint changes.

## Layout

```
routeGeneration/
  types.ts          Layer boundaries — §7 contracts, transcribed
  errors.ts         Error vocabulary; each class carries its own HTTP status
  index.ts          Module's public face + the fixture/real switch
  orchestrator.ts   Layer 2 — the call sequence, written out and wired
  fixtures.ts       Placeholder data. Delete when the orchestrator works.
  domain/           Layer 3 — pure, no provider or DB access
    poiSelector.ts  clusteringEngine.ts  routeOptimizer.ts
    timeEstimator.ts  responseAssembler.ts
  adapters/         Layer 4
    routingProviderAdapter.ts   Interface + GraphHopper/ORS/OSRM shells
    cacheAdapter.ts             Interface + working in-memory impl
  data/             Layer 5
    poiRepository.ts  cityConfigRepository.ts  routeRepository.ts
```

`../routes/routes.ts` is Layer 1. `../../sql/001_route_generation.sql` is the schema.

Two things are implemented rather than stubbed, both because the spec's own
build order asks for them and neither has an external dependency: the in-memory
cache (§9 step 2 — "can start as an in-memory dictionary") and the city-config
TTL cache (it is the mechanism the "config, not code" rollout property rests
on).

## Build order

From spec §9 — bottom-up by dependency, not by layer number. Adapter first
because it carries the highest external uncertainty.

1. **Contracts** — done (`types.ts`).
2. **Adapter** — `routingProviderAdapter.ts` against a real provider with 2–3
   hardcoded coordinate pairs in Algiers. Validate `getRoute` and `getMatrix`.
3. **Data** — repositories, seeded with 5–10 hand-authored fixture POIs.
4. **Domain** — `clusteringEngine` and `responseAssembler` first (pure, no
   dependencies), then `poiSelector` (needs Data), then `routeOptimizer` (needs
   the matrix), then `timeEstimator` last (needs both isochrone and dwell
   times). Unit test each before moving on.
5. **Orchestration** — already wired; it starts working as the pieces land.
6. ~~Driver script~~ — superseded. Layer 1 is built, so `POST /api/routes` is
   the end-to-end check the spec's §9 step 6 script was standing in for.

## The rules that are easy to break

- **One matrix call per request.** `getMatrix` covers every cluster and stop
  pair in a single call, never one call per pair (§4). This is the difference
  between one request and ~400.
- **Cache before every adapter call**, without exception (§2). It is the
  latency lever *and* the quota lever — the two external calls dominate the
  budget, and ordering costs under 1 ms, so no algorithm change will help.
- **Every segment carries its own mode tag** (§5). The AR/UI layer renders
  "drive here, then walk this loop" from that field and must never infer it.
- **Domain never imports a provider SDK** (§2). That is what makes the swap,
  or self-hosting later, a one-file change.
- **Only `status = 'published'` POIs are eligible.** Overpass lands rows as
  `api_seeded` + `draft` for review (§10).

## Deviations from the spec

Marked `NOT IN SPEC` in the code wherever they appear. None are agreed —
confirm before relying on them.

| What | Where | Why |
|---|---|---|
| `pois.checkpoint_radius_meters` | `sql/001` | §3 and §8 require a per-POI checkpoint radius in the response and §10 says it is per-POI configurable, but the schema has nowhere to store it. |
| `pois.photo_*` columns | `sql/001` | The app shows a photo per stop, and the existing catalogue never stores a URL without its licence and attribution. Carried forward rather than regressed. |
| RLS policies | `sql/001` | `routes.user_id` is nullable per spec; without RLS any client could read any route. |
| `RouteRequest.categoryKeys` | `types.ts` | §3 says the POI Selector filters by "theme, category, and city", but §7's request carries only a theme. |
| `POST /api/routes/:id/refine` | `routes/routes.ts` | The app's review step needs it. Spec has no partial-route or refinement concept. Modelled as re-generation, so route immutability survives. |
| Theme list | `fixtures.ts` | Themes have no table. See the note in `poiSelector.ts` — the theme→category mapping needs a home in the schema, or a new city cannot change it without a deploy, which breaks §2's config-not-code property. |

## Testing

Per spec §11, none of which exists yet:

| Level | What |
|---|---|
| Unit | Clustering, the optimizer's ordering step against a fixed known matrix, the assembler, the estimator arithmetic. Fixture-based, run on every change. |
| Repository | Against the 5–10 hand-authored fixture POIs. |
| Adapter | Real provider, 2–3 fixed coordinate pairs, run manually — a stub adapter is used for every automated run so tests never consume free-tier quota. |
| Cache | Assert a cache hit skips the adapter call entirely (mock call-count). |
| End-to-end | `POST /api/routes` against the fixture city: correct segment count, mode tags present, plausible day-count flag. |
