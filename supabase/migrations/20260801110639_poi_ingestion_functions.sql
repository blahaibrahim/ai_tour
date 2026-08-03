-- All three functions are service_role-only write/read machinery for the
-- Flask ingestion pipeline (docs/backend/12). They are never meant to be
-- callable by anon/authenticated — Postgres grants EXECUTE to PUBLIC by
-- default on function creation, so each one explicitly revokes that and
-- re-grants only to service_role, closing that default-open trap.
--
-- NOTE: this revoke-from-public alone turned out to be insufficient — see
-- the follow-up 20260801110806_poi_ingestion_functions_lockdown migration.
-- Supabase separately grants EXECUTE to anon/authenticated directly via
-- ALTER DEFAULT PRIVILEGES, independent of the PUBLIC grant revoked here.
-- Kept as its own migration (rather than folded into this one) to preserve
-- the actual order of what was applied and verified.

create or replace function public.find_location_match(
  p_lat double precision,
  p_lng double precision,
  p_name text,
  p_radius_m double precision default 150,
  p_min_similarity real default 0.6
)
returns text
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select l.id
  from public.locations l
  join public.location_translations t on t.location_id = l.id and t.locale = 'en'
  where st_dwithin(l.geog, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_radius_m)
    and similarity(unaccent(lower(t.name)), unaccent(lower(p_name))) >= p_min_similarity
  order by similarity(unaccent(lower(t.name)), unaccent(lower(p_name))) desc
  limit 1;
$$;

revoke execute on function public.find_location_match(double precision, double precision, text, double precision, real) from public;
grant execute on function public.find_location_match(double precision, double precision, text, double precision, real) to service_role;


create or replace function public.upsert_ingested_location(
  p_id text,
  p_lat double precision,
  p_lng double precision,
  p_category text,
  p_name text,
  p_blurb text,
  p_interest_score numeric,
  p_score_breakdown jsonb,
  p_wikidata_qid text default null,
  p_wikipedia_title text default null,
  p_pageviews_30d integer default null,
  p_heritage_status text default null,
  p_photo_url text default null,
  p_photo_attribution text default null,
  p_photo_license text default null,
  p_photo_source_url text default null,
  p_is_active boolean default true
)
returns void
language plpgsql
security invoker
set search_path = public, extensions
as $$
begin
  -- Curated rows (is_curated = true) are never overwritten by ingestion —
  -- the WHERE clause on the conflict action turns a match against one into
  -- a no-op instead of clobbering hand-verified content.
  insert into public.locations (
    id, category, geog, is_active, interest_score, score_breakdown,
    wikidata_qid, wikipedia_title, pageviews_30d, heritage_status,
    photo_url, photo_attribution, photo_license, photo_source_url, source_count
  ) values (
    p_id, p_category, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_is_active,
    p_interest_score, p_score_breakdown,
    p_wikidata_qid, p_wikipedia_title, p_pageviews_30d, p_heritage_status,
    p_photo_url, p_photo_attribution, p_photo_license, p_photo_source_url, 1
  )
  on conflict (id) do update set
    category          = excluded.category,
    geog              = excluded.geog,
    is_active         = excluded.is_active,
    interest_score    = excluded.interest_score,
    score_breakdown   = excluded.score_breakdown,
    wikidata_qid      = coalesce(excluded.wikidata_qid, public.locations.wikidata_qid),
    wikipedia_title   = coalesce(excluded.wikipedia_title, public.locations.wikipedia_title),
    pageviews_30d     = coalesce(excluded.pageviews_30d, public.locations.pageviews_30d),
    heritage_status   = coalesce(excluded.heritage_status, public.locations.heritage_status),
    photo_url         = coalesce(public.locations.photo_url, excluded.photo_url),
    photo_attribution = coalesce(public.locations.photo_attribution, excluded.photo_attribution),
    photo_license     = coalesce(public.locations.photo_license, excluded.photo_license),
    photo_source_url  = coalesce(public.locations.photo_source_url, excluded.photo_source_url),
    source_count      = public.locations.source_count + 1
  where public.locations.is_curated = false;

  insert into public.location_translations (location_id, locale, name, blurb)
  values (p_id, 'en', p_name, p_blurb)
  on conflict (location_id, locale) do update set
    name = excluded.name, blurb = excluded.blurb
  where exists (
    select 1 from public.locations l where l.id = p_id and l.is_curated = false
  );
end;
$$;

revoke execute on function public.upsert_ingested_location(
  text, double precision, double precision, text, text, text, numeric, jsonb,
  text, text, integer, text, text, text, text, text, boolean
) from public;
grant execute on function public.upsert_ingested_location(
  text, double precision, double precision, text, text, text, numeric, jsonb,
  text, text, integer, text, text, text, text, text, boolean
) to service_role;


create or replace function public.upsert_poi_tile(
  p_tile_id text,
  p_lat_min double precision,
  p_lat_max double precision,
  p_lng_min double precision,
  p_lng_max double precision,
  p_source text,
  p_poi_count integer,
  p_fetch_status text,
  p_ttl_days integer default 60
)
returns void
language plpgsql
security invoker
set search_path = public, extensions
as $$
begin
  insert into public.poi_tiles (tile_id, bounds, source, fetched_at, expires_at, poi_count, fetch_status)
  values (
    p_tile_id,
    st_setsrid(st_makeenvelope(p_lng_min, p_lat_min, p_lng_max, p_lat_max), 4326)::geography,
    p_source, now(), now() + (p_ttl_days || ' days')::interval, p_poi_count, p_fetch_status
  )
  on conflict (tile_id) do update set
    source       = excluded.source,
    fetched_at   = excluded.fetched_at,
    expires_at   = excluded.expires_at,
    poi_count    = excluded.poi_count,
    fetch_status = excluded.fetch_status;
end;
$$;

revoke execute on function public.upsert_poi_tile(text, double precision, double precision, double precision, double precision, text, integer, text, integer) from public;
grant execute on function public.upsert_poi_tile(text, double precision, double precision, double precision, double precision, text, integer, text, integer) to service_role;
