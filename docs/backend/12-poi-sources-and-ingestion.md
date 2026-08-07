# 12 — POI Sources & Ingestion

> Logically this document comes before [02](02-cloud-database-schema.md) and
> [08](08-llm-and-ai-features.md) — it defines where location data comes from.
> It's numbered last only to keep existing cross-links stable.

> **Status: Implemented — but no longer in the request path. Read this first;
> the architecture below changed after it was written.**
>
> This document describes a pipeline that ingests POIs into the `locations`
> catalogue, which route generation then queries. The first half still exists
> and still works. The second half is gone: **`/api/itinerary` and
> `/api/itinerary/modify` now call Overpass live, per request, and never read
> the catalogue.** See the module docstring at the top of
> `backend/server/routes/itinerary.py` for the full reasoning. In short:
>
> - The catalogue made route quality depend on somebody having ingested that
>   area first. A cold city returned only the 8 curated seed rows, which is a
>   worse failure than a slow request.
> - Live Overpass became fast enough for the request path once
>   `ingestion/overpass.py` gained **mirror hedging** (three mirrors, the next
>   started if the previous hasn't answered in 5s, first usable response wins
>   — bounded at roughly one slow mirror's wait instead of the 50–75s floor the
>   old sequential loop could hit) and a **10-minute bbox cache**.
> - Ids are consequently `osm-{type}-{id}` now, not catalogue uuids. That is
>   what forced `saved_locations.location_id` to drop its foreign key (doc 02),
>   and it is what currently breaks `/api/chat` and `/api/tasks/generate`
>   (doc 08).
>
> **The catalogue is empty as of this writing** — `locations`, `poi_tiles` and
> `poi_source_links` all have 0 rows, including the 8 curated seeds. Nothing in
> the running app depends on it. `POST /api/poi/ingest` still works and still
> populates it, and `data/locations_repo.py` still serves from it, but both are
> off the path a user request takes. **Decide deliberately whether to re-seed
> it or retire it** rather than leaving it in this half-state: it is the only
> home for the semantic-search embeddings, the fr/ar translations, and the
> `describe.py` blurb work, all of which are currently built and unused.
>
> **A third source exists on paper:** `backend/server/scripts/ingest_geofabrik.py`
> parses an Algeria OSM PBF extract offline (per doc 13's "offline geographic
> data" layer). It has evidently not been run against the live project — the
> tables it writes to are empty.
>
> ---
>
> **What was built and verified** (as a Flask module,
> `backend/server/ingestion/`, rather than a Supabase Edge Function — see the
> README's architecture-update note). Live and tested against real Overpass,
> Wikidata, Wikipedia, and Commons traffic (not mocked):
>
> - **Fetch** — `ingestion/overpass.py` and `ingestion/wikidata.py`. A real
>   6km-radius query around Constantine returned 11 POIs and 145 nearby
>   Wikidata items; category normalization and name-based filtering both
>   worked as designed on real, messy data (Arabic-named POIs, French
>   place-name tags, etc.).
> - **Score** — `ingestion/scoring.py`, all weights from the table below
>   implemented. Verified on real output: an OSM viewpoint proximity-matched
>   to its Wikidata item (`Monument aux morts de Constantine`) scored 45 with
>   an explainable breakdown; unlinked, lesser-known POIs correctly scored
>   0–10, below the 25 activity floor.
> - **Photos** — `ingestion/photos.py` + `commons.py`. The "approaches
>   evaluated" subsection below was rewritten from an actual empirical test
>   run during implementation, not written speculatively — see that section
>   for what was tried and rejected, and why.
> - **Dedupe** — `find_location_match` (Postgres RPC, trigram + proximity)
>   plus a QID-exact-match check added *after* live testing (see below),
>   wired into `ingestion/ingest.py`. Access-controlled and tested (see doc
>   11's status note for the real gap this testing caught).
> - **Tile cache** — `poi_tiles` table + `ingestion/tiling.py`'s grid
>   covering (a deliberate, documented deviation from this doc's original
>   geohash/H3 suggestion — see that section).
>
> **Now run end-to-end for real**, with `SUPABASE_SERVICE_ROLE_KEY` set: a
> live `POST /api/poi/ingest` call around central Constantine (~4km radius)
> took ~51s, ingested 3 tiles, and persisted 15 new locations alongside the
> 8 curated ones — verified afterward by querying Supabase directly, not
> just trusting the 200 response. `/api/itinerary` then correctly returned a
> mix of curated and newly-ingested stops for the same area, and correctly
> picked the ingested museum specifically when prompted for one.
>
> **Two real bugs surfaced by this run, both fixed and re-verified — not
> caught by the earlier per-component testing, only by running the whole
> thing together against live data:**
>
> 1. **A real duplicate.** The curated `ahmedbey` seed coordinate turned out
>    to be 432m from OSM's actual mapped point for the same building, and
>    OSM's name for it ("Palais du Bey") doesn't trigram-match "Ahmed Bey
>    Palace" — both comfortably outside `find_location_match`'s thresholds.
>    Both records independently resolved to the same Wikidata QID
>    (`Q12232975`) even though neither weaker signal caught it. Fixed by
>    adding an exact-QID lookup as a first check in `ingest.py` (doc 12's own
>    dedup tier 1, "definitive," not previously wired in) and backfilling the
>    QID onto the curated row so future runs match correctly. Re-verified: a
>    second ingestion pass over overlapping ground produced zero duplicates.
> 2. **A worse one: transient failures were being cached as confirmed-empty.**
>    A real Overpass 504 (the shared public instance was under load,
>    reproduced twice) resulted in a tile being marked `fetch_status='ok',
>    poi_count=0` with the normal 60-day TTL — indistinguishable from "this
>    tile genuinely has nothing in it." `overpass.fetch_pois` originally
>    swallowed request failures into an empty list "gracefully"; the actual
>    effect was silently poisoning the cache for two months over a timeout.
>    Fixed by having it raise `OverpassError` instead, so the existing
>    tile-level exception handling (which already did the right thing for
>    every *other* failure mode) also catches this one — re-triggered the
>    same failure for real afterward and confirmed the tile now gets marked
>    `failed` with a 1-day retry TTL instead.
>
> **Deliberately not implemented:** semantic search/embeddings, fr/ar
> translation of ingested content, `poi_merge_overrides`, pre-warming/cron,
> and per-caller rate limiting on the ingestion endpoint (see doc 11's open
> issue #9). `MAX_TILES_PER_INGEST` was cut from 9 to 3 after empirically
> hitting Overpass's rate limit while testing this — real evidence, not a
> cautious guess, and worth knowing before raising it back up.

## What changed

> **Note:** The POI sourcing and ingestion architecture is undergoing a major overhaul to move towards offline OSM extracts and semantic POI cards. See [13 — Route Generation Architecture](13-route-generation-architecture.md) for the new unified pipeline. The notes below reflect the current/legacy implementation.

Route generation is a **three-stage funnel**, not an LLM call:

```
1. FETCH     Maps API → raw tourism POIs near the user
2. SCORE     Deterministic ranking: is this actually worth visiting?
3. SELECT    LLM picks and orders from the top candidates, per the user's prompt
```

This is the right design. The alternative — asking a model to name places near
a coordinate — produces confident hallucinations, stale data, and no
coordinates you can trust. Here the model never invents anything; it only
chooses from rows a maps provider vouched for.

It also changes what `locations` *is*. It was a curated catalogue of 8
hand-written entries. It becomes a **cache of third-party POI data**, which
brings provenance, freshness, deduplication, and licensing along with it.

### The hard part is stage 2

Stage 1 is an HTTP call. Stage 3 is a prompt. **Stage 2 is where the product
lives.**

Raw tourism POI feeds are noisy. An Overpass query for `tourism=*` around
Algiers returns the Casbah alongside a hotel car park, three gift shops, an
unnamed picnic bench, and a `tourism=information` sign. Hand 200 of those to an
LLM and you get a plausible-sounding itinerary built from noise — and you've
paid for the tokens.

Filter hard and cheaply before the model sees anything.

---

## Recommended stack

**OSM/Overpass or Geoapify for coverage · Wikidata + Wikipedia for
interestingness · Wikimedia Commons for photos.**

All free, no billing card, no caching restrictions, and — importantly for this
app — good coverage in Algeria. Djemila, Timgad, the Casbah, and Tassili
n'Ajjer are all UNESCO World Heritage sites with rich Wikidata entries and
multi-language Wikipedia articles. The commercial POI providers are optimised
for restaurants and retail in North American and European markets; for
Algerian heritage they are frequently *worse* than OSM plus Wikidata, not
better.

---

## Provider comparison

Free-tier figures are approximate and change often. **Verify against current
provider docs before depending on any of them.**

### Primary POI sources

| Provider | Key needed | Free tier | Coverage in Algeria | Caching allowed | Verdict |
| --- | --- | --- | --- | --- | --- |
| **Overpass (OSM)** | No | Free; fair-use rate limits on public instances | Good for heritage, variable for detail | Yes — ODbL | **Primary.** No key, no quota anxiety, self-hostable |
| **Geoapify Places** | Yes | Generous daily credit allowance | Same OSM base, cleaner | Yes | **Primary alternative.** Cleaner API than raw Overpass, plus geocoding and routing |
| **OpenTripMap** | Yes | Free tier | OSM + Wikidata merged | Yes | Attractive — ships an importance `rate` field. Verify the service is still actively maintained before depending on it |
| **HERE Browse** | Yes | Daily transaction allowance | Moderate | Limited — check terms | Fallback |
| **TomTom Places** | Yes | Daily request allowance | Moderate | Limited | Fallback |
| **Foursquare Places** | Yes | Developer tier | Thin outside major retail markets | Restricted | Poor fit for this market |
| **Google Places (New)** | Yes + billing card | Monthly credit, then per-call | Best-in-class where it has data | **Heavily restricted** | Optional enrichment only — see below |

### Enrichment sources (all free, no key)

| Source | Gives you | Why it matters |
| --- | --- | --- |
| **Wikidata SPARQL** | Heritage designations, UNESCO status, inception date, coordinates, sitelinks | The single best "is this significant?" signal available |
| **Wikipedia GeoSearch** | Articles near a coordinate | Existence of an article is a strong interestingness filter |
| **Wikipedia REST summary** | Extract, thumbnail, description | Real blurb text in `en`, `fr`, and `ar` — solves content *and* [i18n](09-internationalization.md) at once |
| **Wikipedia Pageviews API** | Monthly views per article | The best free popularity proxy in existence |
| **Wikimedia Commons** | Freely licensed photos | Replaces the `picsum.photos` placeholders in `lib/models/location.dart:77` |

That last row is worth pausing on. `Location.photoUrl` currently returns
`https://picsum.photos/seed/$id/640/900` — random stock images. Commons gives
you actual photographs of the actual place, with clear attribution
requirements you can satisfy. It's a large product upgrade for zero cost.

### On Google Places

Attractive data — ratings, review counts, editorial summaries, photos — and
genuinely the best signal for "will a tourist find this interesting."

But the terms restrict caching and storage of Places content. Place IDs may
generally be retained; most other content may not be stored beyond a limited
window, and derived storage in your own database is constrained. **This
collides directly with the tile-cache architecture below**, which exists to
avoid re-querying the provider.

If you want Google's ratings, the compliant shape is: store the place ID,
fetch live details at request time, don't persist the content. That's a
different (and slower, and metered) design than the one described here. Read
the current terms yourself before building on it — this is a licensing
question, not an engineering one.

**Recommendation: build on OSM + Wikidata.** Revisit Google only if a specific
signal proves missing, and then only as a live-fetch enrichment layer you can
switch off.

---

## Stage 1 — Fetch

### Overpass query

```overpassql
[out:json][timeout:25];
(
  node["tourism"~"^(attraction|museum|artwork|viewpoint|gallery|zoo|aquarium|theme_park)$"](around:{radius},{lat},{lng});
  way ["tourism"~"^(attraction|museum|artwork|viewpoint|gallery)$"](around:{radius},{lat},{lng});

  node["historic"](around:{radius},{lat},{lng});
  way ["historic"](around:{radius},{lat},{lng});

  node["natural"~"^(peak|cave_entrance|arch|spring)$"](around:{radius},{lat},{lng});
  way ["leisure"="park"](around:{radius},{lat},{lng});
  way ["waterway"="waterfall"](around:{radius},{lat},{lng});
);
out center tags;
```

Notes:

- `out center` gives ways and relations a single representative coordinate, so
  everything downstream is a point. Without it, a `way` has no usable position.
- Deliberately **excluded**: `tourism=hotel|hostel|guest_house|apartment`
  (accommodation), `tourism=information` (signs and boards),
  `tourism=picnic_site`, `shop=gift`. These dominate raw results and none of
  them is a stop on a tour.
- `historic=*` unfiltered is intentional — `historic=ruins`,
  `historic=archaeological_site`, `historic=fort`, `historic=monument` are
  exactly this app's subject matter.
- Use a `timeout` and handle 429/504 from public instances gracefully. If
  volume grows, self-host Overpass or move to Geoapify.

**Set a real `User-Agent` with contact details.** OSM services block by
User-Agent, and the app already has this problem — `location_search_bar.dart:75`
sends bare `'ai_tour_app'` to Nominatim with no contact address, which the
usage policy asks for. Fix both at once.

### Ingestion runs server-side

The app **must not** call Overpass directly. Reasons:

1. Rate limits are per-source-IP. Thousands of devices hitting a public
   Overpass instance gets your app's traffic pattern blocked for everyone.
2. Provider keys (Geoapify, HERE) would have to ship in the APK — the same
   problem as [07](07-securing-the-3d-endpoint.md).
3. Every device fetching the same tile independently wastes the provider's
   capacity and the user's battery and data.

One Edge Function (`ingest-pois`) owns all provider access, and the cache is
shared across every user.

---

## The tile cache

> **Implemented, with one deliberate deviation from the plan below:**
> `ingestion/tiling.py` uses a plain equirectangular degree grid
> (`TILE_SIZE_DEG = 0.045`, ~5km cells matching the target size here) instead
> of geohash or H3. Both need either an extra dependency or a non-trivial
> neighbour-enumeration algorithm to correctly cover a circle; a fixed
> lat/lng grid gets the same operational property — deterministic, reusable
> cache keys per patch of ground — in about 15 lines with zero dependencies.
> The code's own comment flags this explicitly as swappable later without
> touching any caller, since every consumer just sees opaque `tile_id`
> strings. `poi_tiles.bounds` is populated via `upsert_poi_tile`'s
> `ST_MakeEnvelope`, not hand-constructed WKT/GeoJSON from the client — see
> the "Ingestion Edge Function" section's status note for why.

This is the piece that makes the whole thing viable.

POI queries are `(lat, lng, radius)`. Caching per query is useless — every
user's center is slightly different, so the hit rate is near zero. Cache by
**tile** instead: snap the request to a fixed grid, fetch and cache whole
tiles, then serve arbitrary radius queries from the cached union.

```
User asks for 12 km around (36.7853, 3.0608)
        │
        ▼
Compute covering tiles (geohash precision 5, ≈ 5 × 5 km)
        │
        ├─ tiles fresh in cache      → serve from Postgres, 0 provider calls
        └─ tiles missing or stale    → fetch those tiles only, upsert, then serve
```

Geohash precision 5 (~4.9 × 4.9 km) is a reasonable cell size for walking-tour
radii. H3 resolution 7 is an equally good choice if you prefer hexagons — no
edge-length distortion with latitude, and neighbour traversal is cleaner.

```sql
create table public.poi_tiles (
  tile_id       text primary key,          -- geohash5 or H3 index
  bounds        geography(Polygon, 4326) not null,
  source        text not null,             -- 'overpass', 'geoapify'
  fetched_at    timestamptz not null,
  expires_at    timestamptz not null,
  poi_count     integer not null default 0,
  fetch_status  text not null default 'ok' -- ok | partial | failed
);

create index poi_tiles_bounds_idx on public.poi_tiles using gist (bounds);
create index poi_tiles_expiry_idx on public.poi_tiles (expires_at);
```

**TTL: 30–90 days.** The Casbah is not going to move. Heritage POI data is
about as static as data gets, and a long TTL is what keeps you inside every
provider's fair-use policy. Contrast with opening hours or ratings, which would
need hours — another reason to avoid depending on those.

Refresh stale tiles **in the background**, serving the stale copy meanwhile.
A user should never wait on a provider round trip; stale-while-revalidate is
the correct policy for data this static.

### Pre-warming

You know where the interesting places are. Pre-fetch tiles covering Algiers,
Constantine, Béjaïa, Timgad, Djemila, and Tassili n'Ajjer at deploy time and
keep them warm on a schedule:

```sql
select cron.schedule('warm-poi-tiles', '0 2 * * 0', $$
  select public.refresh_stale_poi_tiles(limit_tiles => 200);
$$);
```

The first user in Algiers then gets an instant response instead of a 20-second
Overpass query. Given that the app currently ships 8 hardcoded locations in
exactly these areas, the pre-warm list is essentially free to write.

---

## Deduplication

> **Implemented as two checks, run in order** — a change from the original
> single-RPC plan, made *because* live testing exposed a real gap. First: an
> exact Wikidata QID lookup against existing `locations` (signal 1 below,
> "definitive") — added after a live ingestion run produced a genuine
> duplicate that only a QID match caught (the curated `ahmedbey` seed
> coordinate and OSM's mapped point for the same building are 432m apart,
> and the names don't trigram-match — see the top status note for the full
> story). Second, if no QID match: `find_location_match` (Postgres RPC,
> signal 3 — proximity + trigram similarity). Both are locked to
> `service_role` only (see doc 11's status note for the access-control gap
> *that* surfaced during testing — a separate, earlier finding). Re-verified
> after the fix: a second ingestion pass over overlapping ground produced no
> new duplicates. Signals 2 and 4 below are not implemented;
> `poi_source_links`' primary key `(source, source_ref)`
> makes signal 2 (same OSM element across refetches) a natural side effect
> of the upsert rather than something dedup logic needs to check separately.

The same place arrives from multiple sources with different names, slightly
different coordinates, and different ids. "Casbah of Algiers" / "Kasbah
d'Alger" / "قصبة الجزائر" must resolve to one row.

Matching signals, in order of strength:

1. **Wikidata QID** — if two records carry the same QID they are the same
   place. Definitive. OSM's `wikidata=*` tag makes this common.
2. **Same OSM element** (`type` + `id`) across refetches.
3. **Proximity + name similarity** — within 150 m *and* trigram similarity
   > 0.6 on normalized names.
4. **Proximity alone** — within 30 m and same category. Weak; use as a
   tie-breaker only.

```sql
create table public.poi_source_links (
  location_id  text not null references public.locations(id) on delete cascade,
  source       text not null,             -- 'osm' | 'wikidata' | 'geoapify'
  source_ref   text not null,             -- 'node/123456', 'Q188985'
  raw          jsonb not null,            -- original payload, for reprocessing
  fetched_at   timestamptz not null default now(),
  primary key (source, source_ref)
);

create index poi_source_links_loc_idx on public.poi_source_links (location_id);
```

Keeping `raw` means you can re-derive scores and translations when the scoring
model improves, without re-querying anyone.

Name normalization before comparison: lowercase, strip diacritics, drop
leading articles (`the`, `le`, `la`, `el`, `al-`), collapse whitespace. `unaccent`
plus `pg_trgm` handles this in-database:

```sql
select l.id, similarity(unaccent(lower(t.name)), unaccent(lower($1))) as sim
from public.locations l
join public.location_translations t on t.location_id = l.id
where st_dwithin(l.geog, $2::geography, 150)
  and similarity(unaccent(lower(t.name)), unaccent(lower($1))) > 0.6
order by sim desc limit 1;
```

Arabic names won't trigram-match their Latin transliterations. That's fine —
the Wikidata QID join catches those, which is another reason to enrich early.

**Keep a manual override table.** Automated matching will get some pairs wrong,
and you need a way to force a merge or split without redeploying:

```sql
create table public.poi_merge_overrides (
  source text, source_ref text, location_id text, note text,
  primary key (source, source_ref)
);
```

---

## Stage 2 — Interestingness scoring

> **Implemented** — `ingestion/scoring.py`. Every signal in the table below
> is computed, including the log-scaled pageviews curve and the generic-name
> penalty regex. One addition beyond the original spec: a `-30` penalty for
> names matching a generic/retail pattern (parking, WC, ticket office, …)
> short-circuits the rest of scoring entirely rather than just subtracting —
> catches POIs that slipped past Overpass's tag filter with a misleading tag
> but a give-away name. Verified on real data during dry-run testing: an
> OSM `tourism=viewpoint` point named "Monument aux morts," proximity-matched
> to its Wikidata item, scored 45 with breakdown `{multilingual_coverage: 15,
> has_photo: 10, specific_category: 10, corroborated: 10}`; unlinked
> Arabic-named POIs with a specific category but no Wikidata/Wikipedia match
> scored 0–10, correctly below the 25 activity floor. Not yet tuned against
> the 8 curated locations as ground truth (they bypass scoring via
> `is_curated`, so this specific validation doesn't apply the way the
> original plan below assumed — see the note in that subsection).

The core question: **would a traveller be glad they went?**

Compute a deterministic score at ingestion time, store it, and use it to
pre-filter before the LLM. This is cheap, explainable, and debuggable — three
things an LLM judgement is not.

### Signals

| Signal | Weight | Rationale |
| --- | --- | --- |
| UNESCO World Heritage (Wikidata `P1435`) | +40 | Strongest possible endorsement |
| National heritage designation | +25 | Someone official decided it matters |
| Wikipedia article exists | +20 | Somebody wrote about it unprompted |
| Article in ≥ 3 languages | +15 | International significance |
| Wikipedia pageviews (log-scaled) | 0–25 | Actual human interest, measured |
| Commons photos exist | +10 | People travel there and photograph it |
| OSM `wikipedia`/`wikidata` tag present | +8 | Mapper considered it notable |
| OSM tag richness (website, opening_hours, description) | 0–8 | Care taken over the entry |
| Specific category (`museum`, `archaeological_site`) | +10 | vs. generic `attraction` |
| Corroborated by ≥ 2 sources | +10 | Independent agreement |
| Has a name | required | Unnamed POIs are dropped outright |
| Generic/retail name pattern | −30 | "Souvenir Shop", "Parking", "WC" |

```sql
alter table public.locations
  add column interest_score  numeric(6,2) not null default 0,
  add column score_breakdown jsonb,
  add column wikidata_qid    text,
  add column wikipedia_title text,
  add column pageviews_30d   integer,
  add column heritage_status text,
  add column source_count    smallint not null default 1,
  add column is_curated      boolean not null default false;

create index locations_score_idx on public.locations (interest_score desc)
  where is_active;
```

`score_breakdown` as JSONB is worth the column. When someone asks why a place
ranked where it did, you can answer, and when you tune weights you can see what
moved.

`is_curated` is the escape hatch: hand-verified entries (your original 8) that
bypass scoring and are always eligible. **Keep them.** They're known-good, they
give you a regression baseline for the scorer, and they guarantee the app has
content if every provider is down.

### Wikidata enrichment query

```sparql
SELECT ?item ?itemLabel ?heritage ?inception ?image ?article WHERE {
  SERVICE wikibase:around {
    ?item wdt:P625 ?location .
    bd:serviceParam wikibase:center "Point(3.0608 36.7853)"^^geo:wktLiteral .
    bd:serviceParam wikibase:radius "10" .
  }
  OPTIONAL { ?item wdt:P1435 ?heritage . }
  OPTIONAL { ?item wdt:P571  ?inception . }
  OPTIONAL { ?item wdt:P18   ?image . }
  OPTIONAL {
    ?article schema:about ?item ;
             schema:isPartOf <https://en.wikipedia.org/> .
  }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en,fr,ar". }
}
```

One query per tile gives you heritage status, founding date, a Commons image,
and the Wikipedia article — the bulk of the scoring inputs and the blurb source
in three languages. Run it once per tile at ingestion, cache the result in
`poi_source_links.raw`.

Be a good citizen: the public SPARQL endpoint has query-time limits and a
fair-use policy. Batch by tile, don't hammer it, set a `User-Agent`.

### Threshold

Drop anything below a floor (start around 25) at ingestion. Store it with
`is_active = false` rather than deleting — you'll want to retune, and re-running
the scorer over stored `raw` payloads beats refetching.

### Tuning

> **Note on how this landed in practice:** the 8 curated locations were
> seeded with `is_curated = true` and `interest_score = 100` directly (see
> `supabase/seed.sql`), not run through `scoring.py` — they bypass the score
> floor by construction (`nearby_locations`' `is_curated or interest_score >=
> p_min_score` predicate), so "must score in the top decile" doesn't
> literally apply to them as implemented. The spirit of this test still
> matters and hasn't been done: once real ingested POIs exist near a curated
> location (e.g. Timgad), verify the scorer would *independently* rank that
> curated location highly if it went through scoring like everything else —
> that's the real check on whether the weights are sane, not just that the
> hardcoded 100 outranks things (which is true by definition).

Take the 8 hand-picked locations in `lib/models/location_data.dart` as ground
truth. They're all genuinely good stops. **Every one of them must score in the
top decile of its tile.** If Timgad doesn't outrank a car park, the weights are
wrong. Write that as a test.

Longer term, `swipe_decisions` ([02](02-cloud-database-schema.md)) is a
labelled dataset of exactly this judgement — accepted vs. rejected, per user,
per place. Feed aggregate accept rate back in as a signal once you have volume.
This is the strongest reason to persist swipes even though they look ephemeral.

---

## Stage 3 — LLM selection

Detailed in [08](08-llm-and-ai-features.md). The contract with this document:

- Input to the model is the **top 30–50 scored candidates**, never the raw
  feed.
- Each candidate carries: id, name, category, distance, heritage status,
  a one-line description, and the interest score.
- The model returns ids from that set plus a `reason` per pick.
- Every returned id is validated against the candidate set server-side.
- The model **does not** decide travel order — geometry does.

The score is passed to the model as context, not as a ranking to preserve. The
model's job is fit-to-prompt ("somewhere quiet, away from crowds" should
*downrank* the highest-pageview site); the score's job is to guarantee that
everything in the candidate set is worth visiting at all.

That division is the whole design: **the score filters for quality, the model
filters for relevance.**

---

## Photos

Replaces the `picsum.photos` placeholders.

**Implemented** — `backend/server/ingestion/photos.py` and `commons.py`.
What actually shipped differs from the original plan below in two ways,
both discovered by testing rather than decided upfront:

1. **The primary source is the Wikipedia lead image, not Wikidata P18
   directly.** `wikipedia.fetch_summary()` returns a ready-to-use
   `thumbnail_url` in the same call that already fetches the blurb text — no
   separate Commons lookup needed to get *a* usable URL. P18 is still used,
   but only as the second tier, for Wikidata items whose matched Wikipedia
   article (if any) lacks a thumbnail. Testing found real Wikidata P18
   claims that pointed at a wrong or generic image shared across unrelated
   items (`Constantine` and `Sidi Rached Viaduct` both carried
   `image_filename: 'Magnia.jpg'`) — an upstream Wikidata data-quality issue
   that the Wikipedia-first ordering happens to route around for any POI
   with a decent Wikipedia article.
2. **A fourth approach — search-engine-based photo discovery — was tested
   and rejected**, not just considered. See the subsection below for what
   was tried and why it failed a real verification check.

Every resolved photo still carries attribution and license, exactly as
originally planned:

```sql
alter table public.locations
  add column photo_attribution text,
  add column photo_license     text,
  add column photo_source_url  text;
```

`commons.resolve_commons_file()` returns `None` — treated as "no photo,"
not "photo without credit" — if Commons has no `Artist`/`Credit` or
`LicenseShortName` metadata for a file. Verified on a real result: the
Constantine "Monument aux morts" photo came back with attribution
`Bernard Gagnon` and license `CC BY 4.0`, both stored.

**Not yet implemented**: step 3 of the original plan below (fetch once,
store in a `catalogue` Storage bucket, serve from your own CDN path).
Resolved photos are currently stored as direct `upload.wikimedia.org` URLs
on the `locations` row — hotlinking Commons rather than proxying through
Supabase Storage. Doc 05 (not started) is where that would get built; this
was the pragmatic MVP choice to avoid taking on the storage/upload work in
the same pass as the ingestion pipeline itself.

Fall back to a generated placeholder when no image exists — a category glyph on
the `AppTheme` sand/navy palette reads better than a random stock photo of
something else entirely. *(Still not implemented — this is Flutter-side work,
and `photos.resolve_photo()` already returns `None` cleanly for this case to
render against.)*

### Approaches evaluated for the long tail (search-engine-based discovery)

Before settling on the two-tier structured chain above, a third and fourth
approach were tested empirically against a real, obscure ingestion candidate
— a Roman aqueduct near Constantine with no `wikidata=`/`wikipedia=` tags in
OSM — specifically because the structured sources predictably have gaps for
small, local POIs, and the honest question was whether anything could fill
them safely.

**Wikipedia full-text search**, as a name-based fallback for POIs with no
direct Wikidata/Wikipedia link: `srsearch=Aqueduc Romain Constantine
Algeria` returned exactly one hit, "History of the Loiret" — a French
department article with zero relevance. Rejected: fuzzy full-text matching
isn't reliable enough to trust unattended.

**Search-engine image discovery**, both general and Commons-restricted, were
also tested. A general web search for the same aqueduct returned exclusively
paid stock-photo listings (Alamy, Dreamstime, Shutterstock) — unusable
without per-image licensing, and those sites actively block hotlinking
besides. Restricting the search to `commons.wikimedia.org` looked more
promising — the top result was literally titled `File:Aqueduc_romain.JPG` —
but fetching that file's actual Commons categories revealed it depicts a
bridge in **Carrazeda de Ansiães, Portugal**, captioned generically in
French. A real, silent false positive that passed every surface-level check
except actually reading the metadata.

**Conclusion, and why it's not wired into the pipeline:** only structured,
ID-based lookups are trustworthy enough to run unattended — guessing at
*which building a photo depicts* from text similarity fails in ways that are
hard to catch automatically, as the Portugal/Algeria mismatch demonstrates.
Below the two structured tiers, `photos.resolve_photo()` simply returns
`None`. Closing this gap properly means either a bounded human-review queue
(surface the candidate, let a person approve it) or a paid, properly-licensed
provider — not scraping. Full writeup, including why each approach failed,
is in `ingestion/photos.py`'s module docstring, kept next to the code it
justifies rather than only here.

---

## Content and translations

> **Partially implemented.** English-only: `ingestion/ingest.py`'s
> `_truncate_blurb` takes the raw Wikipedia extract and cuts it to ~280
> characters at a sentence boundary, but does **not** run it through an LLM
> rewrite pass for tone — the "encyclopedic, not editorial" caveat below is
> still exactly as true of the stored blurbs as it warns. `fr`/`ar`
> translation isn't implemented at all; only `locale='en'` rows are ever
> written. Both are real, known gaps, not oversights — deferred to keep the
> ingestion pipeline's per-POI cost down (an LLM call per blurb would roughly
> double it) until doc 09 (i18n, not started) makes translated content
> actually renderable.

Wikipedia summaries in `en`, `fr`, and `ar` fill `location_translations`
([09](09-internationalization.md)) directly:

```
GET https://{lang}.wikipedia.org/api/rest_v1/page/summary/{title}
```

Two caveats. Wikipedia extracts are encyclopedic, not editorial — "Djemila is a
small mountain village in Algeria, near the northern coast east of Algiers" is
accurate and flat, where the current hand-written blurb ("A Roman market town
scattered across a mountain ridge, its forum still catching the evening light")
has voice. Consider running extracts through the LLM to rewrite in the app's
register, with the extract as grounding. That keeps it factual and on-tone.

And: Wikipedia is CC BY-SA. Verbatim reuse carries attribution and share-alike
obligations. LLM-rewritten summaries grounded in the extract are a different
question legally — if you reuse text closely, attribute it. Cheapest safe path
is to attribute the source article on the detail screen regardless.

---

## Ingestion Edge Function

> **Implemented differently from the sketch below, on both axes.** It's a
> Flask route (`backend/server/routes/poi.py` → `POST /api/poi/ingest`), not
> a Deno Edge Function — consistent with the whole-project shift to Flask,
> see the README's architecture note. More significantly, it's **fully
> synchronous, not stale-while-revalidate**: there's no `waitUntil`
> equivalent wired up (Flask's dev server has no background-task primitive
> as convenient as Supabase Edge Functions' `EdgeRuntime.waitUntil`), so a
> cold-tile request blocks until every POI in it is fetched, enriched,
> scored, and persisted — which `routes/poi.py`'s own docstring documents
> can take tens of seconds. That's exactly why ingestion is its own
> explicitly-triggered endpoint rather than an automatic step inside
> `/api/itinerary` (see doc 08's status note): synchronous is an acceptable
> trade for a deliberate, bounded backfill call, but not for blocking a
> user's read. Closing this gap for real — background refresh, `waitUntil`-
> style non-blocking staleness — needs either a task queue (Celery/RQ) or
> moving ingestion to something with better async primitives; noted as
> future work, not attempted here.

```typescript
// supabase/functions/ingest-pois/index.ts
Deno.serve(async (req) => {
  const { lat, lng, radius_km } = await req.json();

  const tiles = coveringTiles(lat, lng, radius_km);          // geohash5
  const stale = await findStaleTiles(tiles);                 // missing or expired

  if (stale.length > 0) {
    EdgeRuntime.waitUntil(refreshTiles(stale));              // background
  }

  // Always serve immediately from cache, stale or not
  return json(await queryCachedPois(lat, lng, radius_km));
});
```

`waitUntil` is what makes stale-while-revalidate work — the response goes out
now, the refresh continues after. If a tile has *never* been fetched, block on
that one tile only and let the rest refresh in the background.

Per-tile refresh:

```
Overpass  → normalize → dedupe against existing → upsert locations
                                                → upsert poi_source_links
Wikidata  → enrich (QID, heritage, image, article)
Wikipedia → summaries (en/fr/ar) + pageviews
Score     → interest_score + score_breakdown
Commons   → fetch photo → catalogue bucket
Mark tile fresh
```

**Implemented** (`ingestion/ingest.py`'s `_ingest_one_tile`), with three
differences from this sketch: dedupe happens per-POI via `find_location_match`
rather than as a distinct batch step; `en` only, not `en/fr/ar` (see
"Content and translations" above); and the photo step stores a direct
Commons URL rather than copying into a `catalogue` bucket (see "Photos"
above) — there is no bucket yet.

Make each step idempotent and resumable. Provider failures are routine; a
half-ingested tile must be safe to retry. Track `fetch_status = 'partial'` so
the reconciler knows to come back. **Partially implemented**: a failed tile
is marked `fetch_status = 'failed'` with a 1-day retry TTL (shorter than the
normal 60-day success TTL) so it comes back around soon — but failure is
currently all-or-nothing per tile, not per-POI, so `'partial'` status is
defined in the schema but never actually set by the code yet.

---

## Updated `nearby_locations`

> **Implemented and live** — see doc 02's status note. One addition beyond
> this sketch: the deployed version also returns `is_curated` and orders
> `is_curated desc` first, ahead of score, so the hand-verified 8 always
> surface before ingested content at equal distance.

The RPC in [02](02-cloud-database-schema.md) gains score filtering and ordering:

```sql
create or replace function public.nearby_locations(
  p_lat double precision, p_lng double precision, p_radius_km double precision,
  p_categories text[] default null,
  p_min_score numeric default 25,
  p_locale text default 'en',
  p_limit integer default 50
)
returns table (
  id text, name text, blurb text, category text,
  lat double precision, lng double precision,
  distance_km double precision, interest_score numeric,
  heritage_status text, photo_url text
)
language sql stable security invoker
set search_path = public, extensions
as $$
  select
    l.id,
    coalesce(t.name, ten.name),
    coalesce(t.blurb, ten.blurb),
    l.category,
    st_y(l.geog::geometry), st_x(l.geog::geometry),
    st_distance(l.geog, st_makepoint(p_lng, p_lat)::geography) / 1000.0,
    l.interest_score,
    l.heritage_status,
    l.photo_url
  from public.locations l
  left join public.location_translations t
         on t.location_id = l.id and t.locale = p_locale
  left join public.location_translations ten
         on ten.location_id = l.id and ten.locale = 'en'
  where l.is_active
    and st_dwithin(l.geog, st_makepoint(p_lng, p_lat)::geography, p_radius_km * 1000)
    and (l.is_curated or l.interest_score >= p_min_score)
    and (p_categories is null or l.category = any(p_categories))
  order by l.interest_score desc,
           l.geog <-> st_makepoint(p_lng, p_lat)::geography
  limit least(p_limit, 100);
$$;
```

Two changes worth noting. `p_regions` is gone — regions were a property of the
hand-curated set (`lib/models/location_data.dart:4`) and don't survive contact
with arbitrary geography. `p_categories` replaces it, derived from OSM tags.
The region chips in the map UI become category chips, or are dropped in favour
of the radius control that now actually works.

And ordering is by score first, distance second. For a *browse* that's right.
For the swipe queue you may want distance-first within a score floor — worth an
A/B test once you have `swipe_decisions` data to measure against.

---

## Routing

> **Partially implemented.** `itinerary.py`'s `_order_nearest_neighbor` does
> exactly the "≤ 10 stops" case described below — greedy nearest-neighbour
> from the user's position — but in Python server-side, not Dart client-side
> as originally sketched, and without the 2-opt refinement pass (plain
> nearest-neighbour only). No hosted routing service (OSRM, Valhalla, etc.)
> is integrated, and no route geometry is cached — this app only orders
> stops, it doesn't fetch or display actual road-following polylines yet.

Once the model has selected stops, order them geometrically. Free options:

| Service | Free tier | Notes |
| --- | --- | --- |
| **OSRM** | Public demo server (fair use), self-hostable | Fastest; the demo server is not for production traffic |
| **Valhalla** | FOSSGIS public instance | Good multimodal support, including walking |
| **OpenRouteService** | Daily request allowance with a key | Has a matrix endpoint and TSP-style optimization |
| **GraphHopper** | Free tier with a key | Solid routing plus an optimization API |
| **Geoapify Routing** | Same allowance as their Places API | Convenient if you're already using them for POIs |

For ≤ 10 stops, fetch a distance matrix and solve with nearest-neighbour plus
2-opt in Dart — milliseconds, no extra dependency. Only reach for a hosted
optimization endpoint beyond that.

Cache route geometry keyed by the ordered stop-id list. The same itinerary
recomputed on every screen open is a waste of somebody's quota.

---

## Failure behaviour

> **Partially implemented, and via a different mechanism than sketched
> below for the "provider down" cases.** "No tiles, provider down → serve
> curated only" doesn't need special handling the way this section implies:
> if Overpass/Wikidata are unreachable, `nearby_locations` still serves
> whatever's already in Supabase (curated rows plus any previously-ingested
> POIs) exactly as normal — ingestion just fails to *add* anything new for
> that request, verified via `overpass.fetch_pois` returning `[]` on a real
> 429 without raising. The case this section really describes — **Supabase
> itself unreachable** — is handled one layer up, in `locations_repo.py`
> (docs/backend/02's read path), and was verified in an earlier session by
> pointing the client at a nonexistent host. "Stale tiles serve immediately,
> refresh in background" is **not implemented** — see the "Ingestion Edge
> Function" section's status note on why this pipeline is fully synchronous
> instead.

Providers go down. The app must degrade, not break:

```
Fresh tiles in cache        →  serve
Stale tiles in cache        →  serve stale, refresh in background
No tiles, provider up       →  fetch (show the thinking screen — it's honest now)
No tiles, provider down     →  serve curated locations only, tell the user
                               coverage is limited here
```

The curated 8 are the floor. Never show an empty map.

---

## Testing checklist

- [ ] Overpass query around Algiers returns the Casbah and Maqam Echahid, and excludes hotels and gift shops — not tested against Algiers specifically; the equivalent query around **Constantine** was run for real and correctly returned named, categorized POIs while excluding hotels/gift shops by construction (the query's tag filter never requests those tags in the first place)
- [ ] All 8 curated locations score in the top decile of their tile — n/a as implemented; see the "Tuning" section's note above on why, and what the real equivalent check would be
- [x] Same place from OSM and Wikidata merges into one row via QID — verified for real, the hard way: the *original* dedup design (proximity + trigram only) failed to catch a real duplicate (curated `ahmedbey` vs. OSM's `Palais du Bey`, 432m apart, non-matching names), both sides sharing QID `Q12232975`. Adding an exact-QID check fixed it; a second ingestion pass over the same ground confirmed zero new duplicates
- [ ] Arabic and Latin names for one place do not create two rows — not specifically tested; the QID path covers the case that was actually hit, but a pure name-based Arabic/Latin collision hasn't been exercised
- [x] Second request for the same area makes zero provider calls — verified: tiles marked `fetch_status='ok'` on the first run were correctly skipped (not re-fetched) on the second ingestion call over overlapping ground; only the two previously-`failed`/deleted tiles were retried
- [ ] Stale tile serves immediately and refreshes in the background — **not applicable to the current implementation** — see the "Ingestion Edge Function" status note; ingestion is fully synchronous, there is no background refresh to test
- [x] Provider 429/504 → cached data still served, no user-visible error, tile marked for retry rather than falsely cached as empty — verified for real, twice: a live Overpass 504 initially resulted in a genuine bug (the tile got cached as `fetch_status='ok', poi_count=0` for 60 days — indistinguishable from "really empty"). Fixed by making `overpass.fetch_pois` raise instead of swallowing the failure; re-triggered the same 504 afterward and confirmed the tile now gets `fetch_status='failed'` with a 1-day retry TTL. The endpoint itself still returned 200 with no user-visible error either time
- [ ] Provider fully down with a cold cache → curated locations shown with an explanation — the "curated locations shown" half is verified (see "Failure behaviour" above); the "with an explanation" half is **not implemented** — the fallback is silent, there's no user-facing message distinguishing "nothing here" from "couldn't check"
- [x] Unnamed POIs never reach the candidate set — verified: `overpass.py` drops any element with no resolvable name before it's returned, and none appeared in real query results during testing
- [x] Photo attribution and licence stored and displayed for every Commons image — verified: `commons.resolve_commons_file` returns `None` (not a partial result) when either is missing, and a real resolved photo (Constantine's "Monument aux morts") came back with both fields populated
- [x] Interrupted tile ingestion is safely resumable — verified by the same 504 incident above: the failed tile was correctly retryable (short TTL) rather than stuck in a bad cached state, and a subsequent run successfully completed it
- [x] `nearby_locations` at radius 5 vs. 50 returns materially different sets — verified in an earlier session against curated-only data; unchanged by ingestion since it's the same RPC
