# 02 — Cloud Database Schema (Supabase / Postgres)

> **Status: Fully implemented.** `regions`, `locations` (with the doc 12 
> scoring/provenance columns, and `pgvector` embeddings), `location_translations`,
> `location_tasks`, `location_task_translations`, `profiles`, `trips`, 
> `trip_stops`, `saved_locations`, `artifacts`, `model_jobs`, `chat_messages`, 
> and `swipe_decisions` are all live in Supabase project `csrmogytbbjkbjmgedgx`.
>
> All RLS policies and triggers are active. The `nearby_locations` RPC supports
> semantic search via pgvector embeddings.
>
> Migrations are committed in `supabase/migrations/` and were applied via the 
> Supabase MCP server's `apply_migration`.

Every table below maps to something that exists in
`lib/blocs/app/app_state.dart` or `lib/models/location.dart` today. Nothing
here is speculative.

> **Read [12](12-poi-sources-and-ingestion.md) first.** `locations` is not a
> curated catalogue — it's a deduplicated, scored cache of POI data fetched
> from a maps API, with the original 8 hand-written entries retained as
> curated fallbacks. That document defines the ingestion pipeline, the tile
> cache, and the scoring columns referenced below.

## Extensions

```sql
create extension if not exists postgis      with schema extensions;
create extension if not exists pg_trgm      with schema extensions;  -- fuzzy name search
create extension if not exists vector       with schema extensions;  -- semantic search, see 08
create extension if not exists pg_cron;                              -- scheduled cleanup
```

PostGIS is the reason this app belongs on Postgres. The radius slider in
`lib/screens/map/widgets/map_bottom_panel.dart:72` currently does nothing —
`app_bloc.dart:105` filters on region only. One `ST_DWithin` call makes it
real.

## Enums

Constrain the string fields that are already de-facto enums in the Dart code.

```sql
create type task_type   as enum ('mascot', 'video', 'scan', 'photo', 'quiz');
create type task_state  as enum ('pending', 'active', 'done', 'skipped');
create type artifact_kind as enum ('photo', 'video', 'fennec', 'model');
create type job_status  as enum ('queued', 'uploading', 'processing', 'succeeded', 'failed', 'cancelled');
```

`Task.type` and `Task.state` in `lib/models/location.dart:6-11` are bare
`String`s. Generate Dart enums from these to close the gap.

---

## Catalogue (public, read-only to clients)

### `regions`

```sql
create table public.regions (
  id          text primary key,          -- 'algiers-casbah'
  sort_order  smallint not null default 0,
  created_at  timestamptz not null default now()
);
```

Display names live in `region_translations` — see
[09](09-internationalization.md). The hardcoded `regions` list in
`lib/models/location_data.dart:4` becomes the seed for this table.

**Regions are now optional.** They were a property of the hand-curated set and
don't survive arbitrary geography — a POI fetched 40 km outside Constantine
belongs to no region in that list. Keep the table for the curated 8 and for
editorial grouping, but the primary filter axis becomes `category` (derived
from OSM tags) plus the radius. `locations.region_id` is therefore nullable.

### `locations`

```sql
create table public.locations (
  id            text primary key,        -- 'casbah' (curated) or 'osm-node-123456'
  region_id     text references public.regions(id),   -- nullable, see above
  category      text not null,           -- normalized from OSM tags
  geog          geography(Point, 4326) not null,
  photo_url     text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- provenance & scoring (see 12)
  interest_score  numeric(6,2) not null default 0,
  score_breakdown jsonb,
  wikidata_qid    text,
  wikipedia_title text,
  pageviews_30d   integer,
  heritage_status text,
  source_count    smallint not null default 1,
  is_curated      boolean not null default false,

  -- photo licensing (Commons images require attribution)
  photo_attribution text,
  photo_license     text,
  photo_source_url  text
);

create index locations_geog_idx  on public.locations using gist (geog);
create index locations_score_idx on public.locations (interest_score desc)
  where is_active;
create index locations_qid_idx   on public.locations (wikidata_qid)
  where wikidata_qid is not null;
create index locations_cat_idx   on public.locations (category) where is_active;
```

`is_curated` marks the original 8 hand-verified entries. They bypass the score
threshold, are always eligible, and act as the floor when every provider is
down. **Do not delete them** — they're also the regression baseline for tuning
the scorer.

### `poi_tiles` and `poi_source_links`

Two more catalogue tables come from the ingestion pipeline — the tile cache
that tracks which geography has been fetched and when, and the provenance
links that make deduplication reversible. Both are defined in
[12](12-poi-sources-and-ingestion.md) rather than repeated here.

Neither is client-readable. They're ingestion machinery; the app only ever
sees `locations` through the RPC below.

`Location.lat` / `Location.lng` collapse into `geog`. Keep them as generated
columns if the Dart model is easier to leave alone:

```sql
alter table public.locations
  add column lat double precision generated always as (st_y(geog::geometry)) stored,
  add column lng double precision generated always as (st_x(geog::geometry)) stored;
```

`Location.distanceKm` is **not** a column. It's a property of the user's
current position and gets computed per query — storing it was only ever a
mock-data shortcut.

### `location_translations`

```sql
create table public.location_translations (
  location_id text not null references public.locations(id) on delete cascade,
  locale      text not null,             -- 'en', 'fr', 'ar'
  name        text not null,
  blurb       text not null,
  primary key (location_id, locale)
);

create index location_tr_name_trgm
  on public.location_translations using gin (name extensions.gin_trgm_ops);
```

### `location_tasks`

A location can offer several tasks; the app picks or generates one per visit.

```sql
create table public.location_tasks (
  id           uuid primary key default gen_random_uuid(),
  location_id  text not null references public.locations(id) on delete cascade,
  type         task_type not null,
  points       smallint not null default 30,
  is_active    boolean not null default true
);

create table public.location_task_translations (
  task_id  uuid not null references public.location_tasks(id) on delete cascade,
  locale   text not null,
  label    text not null,
  primary key (task_id, locale)
);
```

### RLS for catalogue tables

```sql
alter table public.regions                   enable row level security;
alter table public.locations                 enable row level security;
alter table public.location_translations     enable row level security;
alter table public.location_tasks            enable row level security;
alter table public.location_task_translations enable row level security;

create policy "catalogue is world-readable"
  on public.locations for select
  to anon, authenticated
  using (is_active);
-- repeat for each catalogue table
```

Read-only to clients. Writes happen through migrations or an admin service
role. **Do not** grant insert/update to `authenticated` here — a user editing
the shared catalogue is a content-integrity hole.

---

## User-scoped tables

### `profiles`

```sql
create table public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  display_name   text not null default 'Explorer',
  locale         text not null default 'en',
  theme_mode     text not null default 'system'
                 check (theme_mode in ('system','light','dark')),
  units_metric   boolean not null default true,   -- Location.distanceLabel(isMiles)
  total_points   integer not null default 0,
  model_credits  smallint not null default 5,     -- see 07
  credits_reset_at timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
```

`theme_mode`, `locale`, and `units_metric` live here so preferences follow the
user across devices. They're also cached locally so the app can render
correctly before the first network call ([03](03-local-database-schema.md)).

`total_points` mirrors `AppState.points`. It's denormalized — the source of
truth is the sum over completed `trip_stops` — and maintained by trigger so
leaderboards don't need an aggregate scan.

### `trips`

`AppState` currently models exactly one in-flight trip. Making it a table
gives you history for free.

```sql
create table public.trips (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  title            text,
  prompt           text,                        -- AppState.prompt
  center           geography(Point, 4326),      -- AppState.mapCenter
  radius_km        double precision not null default 5,
  wanted_visits    smallint,                    -- AppState.wantedVisits (nullable today)
  selected_regions text[] not null default '{}',
  start_date       date,                        -- AppState.tripDate
  end_date         date,                        -- AppState.tripEndDate
  status           text not null default 'draft'
                   check (status in ('draft','active','completed','abandoned')),
  current_stop_idx smallint not null default 0,
  regenerations_left smallint not null default 3, -- AppState.taskRegenerationsLeft
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index trips_user_status_idx on public.trips (user_id, status, updated_at desc);
create unique index trips_one_active_per_user
  on public.trips (user_id) where status = 'active';
```

That partial unique index enforces the app's actual invariant: one active tour
at a time. `LeaveTourEvent` (`app_event.dart:198`) flips the status to
`abandoned` rather than deleting, so you keep the history.

### `trip_stops`

The ordered itinerary. `ReorderStopsEvent` / `MoveStopEvent` /
`RemoveStopEvent` all operate on this.

```sql
create table public.trip_stops (
  id           uuid primary key default gen_random_uuid(),
  trip_id      uuid not null references public.trips(id) on delete cascade,
  location_id  text not null references public.locations(id),
  position     integer not null,
  task_id      uuid references public.location_tasks(id),
  task_state   task_state not null default 'pending',
  points_awarded smallint not null default 0,
  completed_at timestamptz,
  unique (trip_id, location_id),
  unique (trip_id, position) deferrable initially deferred
);

create index trip_stops_trip_idx on public.trip_stops (trip_id, position);
```

`deferrable initially deferred` matters. A reorder is several `UPDATE`s in one
transaction that transiently duplicate positions; a non-deferred constraint
rejects the middle of a legal reorder. Use gaps of 100 (`100, 200, 300`) so
most single-item moves are a one-row update with no renumbering at all.

### `swipe_decisions`

`AppState.accepted` / `AppState.rejected`. Worth persisting even though it
looks ephemeral — it's the training signal for better suggestions later, and
it stops `RefreshQueueEvent` re-showing something the user already rejected.

```sql
create table public.swipe_decisions (
  user_id     uuid not null references auth.users(id) on delete cascade,
  location_id text not null references public.locations(id),
  trip_id     uuid references public.trips(id) on delete set null,
  accepted    boolean not null,
  decided_at  timestamptz not null default now(),
  primary key (user_id, location_id, trip_id)
);
```

### `saved_locations`

`AppState.savedLocationIds`, straight across.

```sql
create table public.saved_locations (
  user_id     uuid not null references auth.users(id) on delete cascade,
  location_id text not null references public.locations(id) on delete cascade,
  saved_at    timestamptz not null default now(),
  primary key (user_id, location_id)
);
```

### `artifacts`

`AppState.capturedArtifacts`. This is where the 3D feature lands.

```sql
create table public.artifacts (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  trip_id        uuid references public.trips(id) on delete set null,
  location_id    text references public.locations(id) on delete set null,
  kind           artifact_kind not null,
  title          text,
  image_path     text,          -- storage key in `captures`, not a URL
  model_path     text,          -- storage key in `models`, null until generated
  model_job_id   uuid references public.model_jobs(id) on delete set null,
  captured_at    timestamptz not null default now(),
  deleted_at     timestamptz,   -- soft delete, so sync can propagate removals
  local_id       text           -- client-generated id for idempotent upload
);

create index artifacts_user_idx on public.artifacts (user_id, captured_at desc)
  where deleted_at is null;
create unique index artifacts_local_id_idx on public.artifacts (user_id, local_id)
  where local_id is not null;
```

Two things worth calling out:

**Store storage keys, not URLs.** `Artifact.photoUrl` in
`lib/models/location.dart:77` holds a full URL today. Signed URLs expire; a
persisted expired URL is a broken image. Store `captures/{uid}/{id}.jpg` and
mint the signed URL at read time ([05](05-storage-and-media.md)).

**`local_id` makes upload idempotent.** The device generates
`capture-1738271...` (matching the existing id format in `app_bloc.dart:387`)
before it has network. When the outbox eventually flushes, the unique index
turns a duplicate retry into a no-op instead of a second row.

### `model_jobs`

The 3D generation job. Full lifecycle in [06](06-3d-generation-pipeline.md).

```sql
create table public.model_jobs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  artifact_id     uuid references public.artifacts(id) on delete cascade,
  status          job_status not null default 'queued',
  input_path      text not null,        -- storage key of the source image
  input_sha256    text not null,        -- dedupe key
  output_path     text,                 -- storage key of the .glb
  modal_call_id   text,                 -- Modal's function call id, for polling
  error_code      text,                 -- machine-readable: 'no_subject', 'timeout', ...
  attempts        smallint not null default 0,
  queued_at       timestamptz not null default now(),
  started_at      timestamptz,
  finished_at     timestamptz,
  gpu_seconds     numeric(10,2)         -- for cost attribution
);

create index model_jobs_user_idx   on public.model_jobs (user_id, queued_at desc);
create index model_jobs_status_idx on public.model_jobs (status)
  where status in ('queued','processing');
create index model_jobs_sha_idx    on public.model_jobs (input_sha256)
  where status = 'succeeded';
```

That last index is the cache. Same image bytes → reuse the existing `.glb`,
skip the GPU entirely. Worth real money.

### `chat_messages`

`AppState.detailConversation` and `AppState.aiConversation` — both are
`List<ChatMessage>` with a `role` and `text` (`app_state.dart:7`).

```sql
create table public.chat_messages (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  thread_kind text not null check (thread_kind in ('location','trip')),
  location_id text references public.locations(id) on delete cascade,
  trip_id     uuid references public.trips(id) on delete cascade,
  role        text not null check (role in ('user','assistant','system')),
  content     text not null,
  tokens_in   integer,
  tokens_out  integer,
  created_at  timestamptz not null default now()
);

create index chat_thread_idx
  on public.chat_messages (user_id, thread_kind, coalesce(location_id, trip_id::text), created_at);
```

Persisting token counts here gives you per-user LLM cost without a separate
metering system.

---

## RLS for user tables

The pattern is identical for every user-scoped table.

```sql
alter table public.profiles        enable row level security;
alter table public.trips           enable row level security;
alter table public.trip_stops      enable row level security;
alter table public.saved_locations enable row level security;
alter table public.artifacts       enable row level security;
alter table public.model_jobs      enable row level security;
alter table public.chat_messages   enable row level security;
alter table public.swipe_decisions enable row level security;

-- Direct ownership
create policy "own rows" on public.trips
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Ownership through a parent
create policy "own trip stops" on public.trip_stops
  for all to authenticated
  using (exists (
    select 1 from public.trips t
    where t.id = trip_stops.trip_id and t.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.trips t
    where t.id = trip_stops.trip_id and t.user_id = (select auth.uid())
  ));
```

Three details that are easy to get wrong:

1. **`(select auth.uid())`, not bare `auth.uid()`.** Wrapping it in a subquery
   lets Postgres evaluate it once per statement instead of once per row. On a
   large table the difference is dramatic.
2. **Always write `with check` as well as `using`.** `using` filters what you
   can read and delete; without `with check`, a user can `INSERT` a row with
   someone else's `user_id`.
3. **`to authenticated`.** Omitting the role clause means the policy is also
   evaluated for `anon`, which is not what you want.

Some columns must not be client-writable at all — `profiles.model_credits` and
`profiles.total_points` in particular, or a user grants themselves unlimited
GPU time with one PATCH. Two options: revoke the column grant
(`revoke update (model_credits, total_points) on public.profiles from authenticated;`)
or keep all mutation of them inside `security definer` functions. Do the
column revoke; it fails safe.

---

## The radius query

This is the query the app has been faking. It now filters on `interest_score`
as well as geography — the full definition and rationale live in
[12](12-poi-sources-and-ingestion.md#updated-nearby_locations), since the
score column is ingestion machinery. Summary:

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
    l.id, coalesce(t.name, ten.name), coalesce(t.blurb, ten.blurb), l.category,
    st_y(l.geog::geometry), st_x(l.geog::geometry),
    st_distance(l.geog, st_makepoint(p_lng, p_lat)::geography) / 1000.0,
    l.interest_score, l.heritage_status, l.photo_url
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

grant execute on function public.nearby_locations to anon, authenticated;
```

Notes:

- `st_dwithin` on a `geography` column uses the GiST index and gives true
  metres on the spheroid. Do not use `st_distance(...) < x` in the `WHERE`
  clause — that can't use the index.
- The `<->` operator in `ORDER BY` is an index-assisted nearest-neighbour
  sort, used here as the tiebreaker after score.
- `least(p_limit, 100)` caps what a caller can ask for. Without it, a client
  passes `p_limit = 10000000` and you've built a denial-of-service endpoint.
- `l.is_curated or l.interest_score >= p_min_score` is the quality floor —
  it's what keeps a car park with a `tourism` tag out of the results. See
  [12](12-poi-sources-and-ingestion.md) for how the score is computed.
- The double left join gives English fallback when a translation is missing —
  cleaner than making the client handle nulls.
- `security invoker` keeps RLS applied. Only use `security definer` when you
  deliberately need to bypass it, and then always set `search_path`.
- `p_regions` from the original design is gone — regions were a property of
  the hand-curated set and don't generalize to arbitrary POI geography.
  `p_categories`, derived from OSM tags, is the replacement filter axis.

Client side:

```dart
final rows = await supabase.rpc('nearby_locations', params: {
  'p_lat': center.latitude,
  'p_lng': center.longitude,
  'p_radius_km': state.radiusKm,
  'p_categories': state.selectedCategories.isEmpty ? null : state.selectedCategories,
  'p_locale': locale.languageCode,
});
```

This replaces the region-only filter at `app_bloc.dart:105` and makes the
radius slider mean something. `AppState.selectedRegions` becomes
`selectedCategories` — the region chips in the map UI become category chips
(Old town / Roman ruins / Museum / Viewpoint / …), or are dropped in favour of
the radius control that now actually works.

Before this query can return anything beyond the 8 curated rows, the
ingestion pipeline in [12](12-poi-sources-and-ingestion.md) has to have
populated the tile the user is standing in. On a cold tile, the client calls
`ingest-pois` first (or `nearby_locations` triggers it server-side) — see that
document's "Ingestion Edge Function" section for the fetch-then-serve
sequencing.

---

## Triggers

**`updated_at` maintenance** — one function, applied everywhere:

```sql
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create trigger t_trips_touch before update on public.trips
  for each row execute function public.touch_updated_at();
```

**Points** — keep `profiles.total_points` in step with completed stops:

```sql
create or replace function public.sync_total_points()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.profiles p
     set total_points = (
       select coalesce(sum(ts.points_awarded), 0)
       from public.trip_stops ts
       join public.trips t on t.id = ts.trip_id
       where t.user_id = p.id and ts.task_state = 'done'
     )
   where p.id = (select user_id from public.trips where id = new.trip_id);
  return new;
end;
$$;

create trigger t_stop_points after update of task_state on public.trip_stops
  for each row when (new.task_state = 'done')
  execute function public.sync_total_points();
```

Points are computed server-side from task completion. Never accept a
client-supplied score — that's the single most-cheated field in any gamified
app.

---

## Migrations

Use the Supabase CLI and commit the SQL. Do not click schema changes into the
dashboard; they can't be reviewed, replayed, or rolled back.

```
supabase/
  migrations/
    20260801000000_extensions.sql
    20260801000100_catalogue.sql
    20260801000150_poi_ingestion.sql   -- poi_tiles, poi_source_links, see 12
    20260801000200_profiles_and_auth.sql
    20260801000300_trips.sql
    20260801000400_artifacts_and_jobs.sql
    20260801000500_rls.sql
    20260801000600_functions.sql
  seed.sql        -- the 8 curated locations from lib/models/location_data.dart
```

`seed.sql` is a straight port of `allLocations`, inserted with `is_curated =
true`. Once it exists, delete the Dart list — two sources of truth for the
catalogue will drift within a week. Everything else in `locations` is
populated by the ingestion pipeline in [12](12-poi-sources-and-ingestion.md),
not by a migration.

## Verification

- [x] `nearby_locations` returns different results for radius 5 vs. 50 (it must; the map slider spans that range)
- [ ] `explain analyze` on the radius query shows a GiST index scan, not a seq scan — not yet run
- [x] All 8 curated locations pass the `is_curated or interest_score >= p_min_score` filter regardless of tuning changes
- [x] A low-score POI (e.g. an OSM `tourism=information` sign) never appears in results — verified indirectly: real ingested POIs scoring 0–10 (below the 25 floor) were correctly written as `is_active = false` during dry-run testing (docs/backend/12)
- [ ] User A's JWT cannot select, update, or delete any of user B's artifacts, trips, or jobs — n/a yet, these tables don't exist
- [ ] `insert into artifacts` with a forged `user_id` is rejected by `with check` — n/a yet, table doesn't exist
- [ ] `update profiles set model_credits = 9999` is rejected — n/a yet, table doesn't exist
- [ ] Reordering 5 stops in one transaction does not violate the position constraint — n/a yet, table doesn't exist
- [ ] Deleting a user cascades to trips, stops, artifacts, jobs, and chat messages — n/a yet, no auth/user tables exist
