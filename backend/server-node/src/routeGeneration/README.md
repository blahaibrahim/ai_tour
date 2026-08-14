# Route Generation Module

Implements the layering in *Route Generation Module — Technical Design
Specification v1.0*. **All five layers are built.** The pipeline runs
end to end against Supabase: three pilot cities, 35 published POIs, real
clustering, TSP ordering, time estimation and persistence.

## Current behaviour

`ROUTE_GENERATION_MODE` (env, default `real`):

| Value | What the endpoints do |
|---|---|
| `real` | Run `orchestrator.ts` against the `pois` / `cities` / `themes` tables. |
| `fixture` | Serve `fixtures.ts` — a two-cluster Algiers route, invented. For working on the app with no database, no provider key and no network. Logs a loud warning at boot. |

## The routing provider

`GRAPHHOPPER_API_KEY` (env) selects the real adapter. **With no key set the
module still works**, but `StraightLineRoutingProvider` stands in and every
duration and distance becomes a great-circle estimate with a 1.35 detour
factor — it says so in the logs on every construction. That is deliberate: the
alternative is a 503 on every request on any machine without a key, which makes
the module impossible to develop or demo against.

Rate limiting is a process-wide token bucket (`ROUTING_PROVIDER_RPS`,
`ROUTING_PROVIDER_BURST`), not a fixed sleep. It costs nothing when calls are
spread out and throttles only when they genuinely bunch up.

## Caching

Three kinds of entry, all behind `CacheAdapter`, all currently in-memory with
a TTL:

| Entry | Key | TTL | Calls saved |
|---|---|---|---|
| Matrix | city + profile + **fingerprint of the exact point set** | 24 h | 1–2 per request |
| Isochrone | POI + 15-min budget bucket + profile | 24 h | 1 per request |
| **Leg** (NOT IN SPEC) | **coordinate pair + profile, nothing else** | 7 d | **one per hop** — the bulk |

Two of these are worth explaining.

**The matrix key is a coordinate fingerprint, not a point count.** The
reference implementation keys on `mode:pointCount`, which returns one point
set's matrix for any other set of the same size — and its own pipeline trips
that immediately, caching the walking matrix over the unordered POI list and
then reading it back for the *ordered* list. Same length, same profile, wrong
rows. The travel times come out plausible and wrong.

**Leg keys carry no city, theme or route id.** That is the whole point: the
Casbah→Ketchaoua walk is the same leg in a history route, a culture route and
an everything route, at every time budget, for every traveller. Scoping it to
the request that created it would throw away almost all of its value.
Direction *is* part of the key — A→B and B→A differ on a one-way street.

Measured against a live GraphHopper free key, Algiers:

```
history (cold)             14.5s   8/10 segments with real geometry
history (warm)              6.0s   8/10
all (shares history legs)   9.4s  14/14
all (warm)                  0.6s  14/14
```

The third line is the one to notice. Cached legs did not just make it faster —
they made it *better*: with half the hops served from cache, the remaining
calls fit inside the free plan's per-minute limit, so every segment came back
with real geometry where an uncached run had produced none.

Failures are deliberately **not** cached. An estimate stored for a week would
keep being served long after the rate limit that caused it had cleared.

### Backends

`REDIS_URL` picks one, decided once at boot by `initCache()` and logged:

| `REDIS_URL` | Backend |
|---|---|
| unset | `InMemoryCacheAdapter` — process-local, cold after every restart |
| set and answering | `ResilientCacheAdapter(RedisCacheAdapter)` — durable, shared across replicas |
| set but unreachable | in-memory, with the reason in the startup log |

Any `redis://` / `rediss://` URL works — a local container, Redis Cloud,
Upstash — because only GET and SET-with-expiry are used.

```bash
docker run -d -p 6379:6379 redis:7-alpine
# backend/.env
REDIS_URL=redis://localhost:6379
```

**Redis is wrapped, not trusted.** The reference implementation commits to a
backend at boot, so a Redis that dies an hour later makes every cache read
throw — and the orchestrator's `cache.getMatrix` call is not inside its try
block, which turns a cache outage into a 500 on a request that could have been
answered by just asking the provider. Everything in this cache is recomputable
by definition, so `ResilientCacheAdapter` reads through to memory on any Redis
error and writes to both. An outage costs latency and quota, never a request.

### Not done

- **`warmActiveCityMatrices`** (spec §8's nightly job) is a stub. With the leg
  cache in place the version worth writing warms legs, not just matrices —
  and with Redis behind it, warming is now worth doing at all, since the
  result outlives the process that did it.

## Tests

`npm test` runs `src/testRouteGeneration.ts`: the pure domain layer against
fixed inputs, then a live end-to-end generation per theme when `SUPABASE_URL`
is set (skipped loudly when it is not). No test run ever calls a routing
provider — the straight-line adapter stands in, so free-tier quota is never
spent (spec §11).

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
