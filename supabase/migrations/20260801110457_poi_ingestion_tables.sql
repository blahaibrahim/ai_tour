-- docs/backend/12 — ingestion machinery, not client-readable. RLS enabled
-- with zero policies for anon/authenticated (default deny); only the
-- service_role (used exclusively by the Flask ingestion module, never the
-- read-path anon client) can touch these.
create table public.poi_tiles (
  tile_id      text primary key,
  bounds       geography(Polygon, 4326) not null,
  source       text not null,
  fetched_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  poi_count    integer not null default 0,
  fetch_status text not null default 'ok' check (fetch_status in ('ok', 'partial', 'failed'))
);

create index poi_tiles_expiry_idx on public.poi_tiles (expires_at);

create table public.poi_source_links (
  location_id text not null references public.locations(id) on delete cascade,
  source      text not null,
  source_ref  text not null,
  raw         jsonb not null,
  fetched_at  timestamptz not null default now(),
  primary key (source, source_ref)
);

create index poi_source_links_loc_idx on public.poi_source_links (location_id);

alter table public.poi_tiles        enable row level security;
alter table public.poi_source_links enable row level security;
