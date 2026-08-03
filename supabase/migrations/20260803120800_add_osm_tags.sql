-- Add osm_tags column to locations
alter table public.locations add column if not exists osm_tags jsonb default '{}'::jsonb;

-- Drop the old function
drop function if exists public.upsert_ingested_location(text, double precision, double precision, text, text, text, numeric, jsonb, text, text, integer, text, text, text, text, text, boolean, vector);
drop function if exists public.upsert_ingested_location(text, double precision, double precision, text, text, text, numeric, jsonb, text, text, integer, text, text, text, text, text, boolean);

-- Recreate with p_osm_tags
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
  p_is_active boolean default true,
  p_embedding vector(384) default null,
  p_osm_tags jsonb default '{}'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = public, extensions
as $$
begin
  insert into public.locations (
    id, category, geog, is_active, interest_score, score_breakdown,
    wikidata_qid, wikipedia_title, pageviews_30d, heritage_status,
    photo_url, photo_attribution, photo_license, photo_source_url, source_count, embedding, osm_tags
  ) values (
    p_id, p_category, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_is_active,
    p_interest_score, p_score_breakdown,
    p_wikidata_qid, p_wikipedia_title, p_pageviews_30d, p_heritage_status,
    p_photo_url, p_photo_attribution, p_photo_license, p_photo_source_url, 1, p_embedding, p_osm_tags
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
    source_count      = public.locations.source_count + 1,
    embedding         = coalesce(excluded.embedding, public.locations.embedding),
    osm_tags          = coalesce(excluded.osm_tags, public.locations.osm_tags)
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
  text, text, integer, text, text, text, text, text, boolean, vector, jsonb
) from public;

grant execute on function public.upsert_ingested_location(
  text, double precision, double precision, text, text, text, numeric, jsonb,
  text, text, integer, text, text, text, text, text, boolean, vector, jsonb
) to service_role;
