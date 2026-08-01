# 12 — POI Sources & Ingestion

> Logically this document comes before [02](02-cloud-database-schema.md) and
> [08](08-llm-and-ai-features.md) — it defines where location data comes from.
> It's numbered last only to keep existing cross-links stable.

## What changed

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

1. Wikidata `P18` gives a Commons filename.
2. Resolve to a thumbnail URL via the Commons API at the size you need.
3. Fetch once, store in the `catalogue` bucket ([05](05-storage-and-media.md)),
   serve from your own CDN path.
4. **Store the attribution** — author and licence — and display it. Commons
   images are freely licensed, not public domain; most require credit.

```sql
alter table public.locations
  add column photo_attribution text,
  add column photo_license     text,
  add column photo_source_url  text;
```

Fall back to a generated placeholder when no image exists — a category glyph on
the `AppTheme` sand/navy palette reads better than a random stock photo of
something else entirely.

---

## Content and translations

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

Make each step idempotent and resumable. Provider failures are routine; a
half-ingested tile must be safe to retry. Track `fetch_status = 'partial'` so
the reconciler knows to come back.

---

## Updated `nearby_locations`

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

- [ ] Overpass query around Algiers returns the Casbah and Maqam Echahid, and excludes hotels and gift shops
- [ ] All 8 curated locations score in the top decile of their tile
- [ ] Same place from OSM and Wikidata merges into one row via QID
- [ ] Arabic and Latin names for one place do not create two rows
- [ ] Second request for the same area makes zero provider calls
- [ ] Stale tile serves immediately and refreshes in the background
- [ ] Provider 429 → cached data still served, no user-visible error
- [ ] Provider fully down with a cold cache → curated locations shown with an explanation
- [ ] Unnamed POIs never reach the candidate set
- [ ] Photo attribution and licence stored and displayed for every Commons image
- [ ] Interrupted tile ingestion is safely resumable
- [ ] `nearby_locations` at radius 5 vs. 50 returns materially different sets
