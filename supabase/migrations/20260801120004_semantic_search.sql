-- Semantic search migration
create extension if not exists vector schema extensions;

alter table public.locations add column if not exists embedding vector(384);
create index if not exists locations_embedding_idx on public.locations using hnsw (embedding vector_cosine_ops);

-- Drop the old upsert_ingested_location so we can replace it with the new signature
drop function if exists public.upsert_ingested_location(text, double precision, double precision, text, text, text, numeric, jsonb, text, text, integer, text, text, text, text, text, boolean);

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
  p_embedding vector(384) default null
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
    photo_url, photo_attribution, photo_license, photo_source_url, source_count, embedding
  ) values (
    p_id, p_category, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_is_active,
    p_interest_score, p_score_breakdown,
    p_wikidata_qid, p_wikipedia_title, p_pageviews_30d, p_heritage_status,
    p_photo_url, p_photo_attribution, p_photo_license, p_photo_source_url, 1, p_embedding
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
    embedding         = coalesce(excluded.embedding, public.locations.embedding)
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
  text, text, integer, text, text, text, text, text, boolean, vector
) from public;
grant execute on function public.upsert_ingested_location(
  text, double precision, double precision, text, text, text, numeric, jsonb,
  text, text, integer, text, text, text, text, text, boolean, vector
) to service_role;


drop function if exists public.nearby_locations(double precision, double precision, double precision, text[], numeric, text, integer);

create or replace function public.nearby_locations(
  p_lat        double precision,
  p_lng        double precision,
  p_radius_km  double precision,
  p_categories text[] default null,
  p_min_score  numeric default 25,
  p_locale     text default 'en',
  p_limit      integer default 50,
  p_prompt_embedding vector(384) default null
)
returns table (
  id              text,
  name            text,
  blurb           text,
  category        text,
  lat             double precision,
  lng             double precision,
  distance_km     double precision,
  interest_score  numeric,
  heritage_status text,
  photo_url       text,
  is_curated      boolean
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select
    l.id,
    coalesce(t.name, ten.name)   as name,
    coalesce(t.blurb, ten.blurb) as blurb,
    l.category,
    st_y(l.geog::geometry),
    st_x(l.geog::geometry),
    st_distance(l.geog, st_makepoint(p_lng, p_lat)::geography) / 1000.0,
    l.interest_score,
    l.heritage_status,
    l.photo_url,
    l.is_curated
  from public.locations l
  left join public.location_translations t
         on t.location_id = l.id and t.locale = p_locale
  left join public.location_translations ten
         on ten.location_id = l.id and ten.locale = 'en'
  where l.is_active
    and st_dwithin(l.geog, st_makepoint(p_lng, p_lat)::geography, p_radius_km * 1000)
    and (l.is_curated or l.interest_score >= p_min_score)
    and (p_categories is null or l.category = any(p_categories))
  order by 
    case when p_prompt_embedding is not null then l.embedding <=> p_prompt_embedding else 0 end asc,
    l.is_curated desc, 
    l.interest_score desc,
    l.geog <-> st_makepoint(p_lng, p_lat)::geography
  limit least(p_limit, 100);
$$;

grant execute on function public.nearby_locations(
  double precision, double precision, double precision, text[], numeric, text, integer, vector
) to anon, authenticated;
