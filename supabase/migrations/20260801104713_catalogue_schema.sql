-- Extensions needed for the POI catalogue (docs/backend/02, /12)
create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------
create type public.task_type as enum ('mascot', 'video', 'scan', 'photo', 'quiz');

-- ---------------------------------------------------------------------
-- Regions — editorial grouping for the curated set. Nullable on locations
-- because live POI data fetched later (docs/backend/12) won't always fall
-- inside one of these hand-picked groups.
-- ---------------------------------------------------------------------
create table public.regions (
  id         text primary key,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now()
);

create table public.region_translations (
  region_id text not null references public.regions(id) on delete cascade,
  locale    text not null,
  name      text not null,
  primary key (region_id, locale)
);

-- ---------------------------------------------------------------------
-- Locations — a deduplicated, scored cache of POI data (curated now,
-- live-ingested later). See docs/backend/12 for the scoring/provenance
-- columns and docs/backend/02 for the base shape.
-- ---------------------------------------------------------------------
create table public.locations (
  id          text primary key,
  region_id   text references public.regions(id),
  category    text not null,
  geog        geography(Point, 4326) not null,
  photo_url   text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  interest_score  numeric(6,2) not null default 0,
  score_breakdown jsonb,
  wikidata_qid    text,
  wikipedia_title text,
  pageviews_30d   integer,
  heritage_status text,
  source_count    smallint not null default 1,
  is_curated      boolean not null default false,

  photo_attribution text,
  photo_license     text,
  photo_source_url  text
);

create index locations_geog_idx  on public.locations using gist (geog);
create index locations_score_idx on public.locations (interest_score desc) where is_active;
create index locations_qid_idx   on public.locations (wikidata_qid) where wikidata_qid is not null;
create index locations_cat_idx   on public.locations (category) where is_active;

create table public.location_translations (
  location_id text not null references public.locations(id) on delete cascade,
  locale      text not null,
  name        text not null,
  blurb       text not null,
  primary key (location_id, locale)
);

create index location_tr_name_trgm
  on public.location_translations using gin (name extensions.gin_trgm_ops);

create table public.location_tasks (
  id          uuid primary key default gen_random_uuid(),
  location_id text not null references public.locations(id) on delete cascade,
  type        public.task_type not null,
  points      smallint not null default 30,
  is_active   boolean not null default true
);

create index location_tasks_loc_idx on public.location_tasks (location_id) where is_active;

create table public.location_task_translations (
  task_id uuid not null references public.location_tasks(id) on delete cascade,
  locale  text not null,
  label   text not null,
  primary key (task_id, locale)
);

-- ---------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger t_locations_touch
  before update on public.locations
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- RLS — catalogue is world-readable, admin/service-role write only.
-- No insert/update/delete policy is granted to anon or authenticated:
-- writes happen via MCP/migrations today, an ingestion service later.
-- ---------------------------------------------------------------------
alter table public.regions                    enable row level security;
alter table public.region_translations         enable row level security;
alter table public.locations                   enable row level security;
alter table public.location_translations       enable row level security;
alter table public.location_tasks              enable row level security;
alter table public.location_task_translations  enable row level security;

create policy "regions are world-readable"
  on public.regions for select to anon, authenticated using (true);

create policy "region translations are world-readable"
  on public.region_translations for select to anon, authenticated using (true);

create policy "active locations are world-readable"
  on public.locations for select to anon, authenticated using (is_active);

create policy "location translations are world-readable"
  on public.location_translations for select to anon, authenticated using (true);

create policy "active location tasks are world-readable"
  on public.location_tasks for select to anon, authenticated using (is_active);

create policy "location task translations are world-readable"
  on public.location_task_translations for select to anon, authenticated using (true);
