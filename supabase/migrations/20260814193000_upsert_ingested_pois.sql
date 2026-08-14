-- Bulk upsert for POIs ingested from OpenStreetMap.
--
-- An RPC rather than a PostgREST insert for the same reason the reads are:
-- `pois.location` is a geography, and PostgREST cannot build one from a lat and
-- a lng. Takes the whole batch as jsonb so one city is one round trip.
--
-- `external_ref` is the identity — 'osm:node/123456' — so a re-run adopts the
-- rows it wrote last time instead of duplicating the city.
--
-- Hand-verified rows are never clobbered: a row whose source is 'team_seeded'
-- or 'ministry_provided', or which someone has already reviewed
-- (verified_by is not null), is left exactly as it is. Ingestion is allowed to
-- discover places, not to overwrite the judgement of whoever checked one.
create or replace function public.upsert_ingested_pois(p_rows jsonb)
returns integer
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_written integer := 0;
begin
  with incoming as (
    select
      (r->>'city_id')::uuid                       as city_id,
      (r->>'category_id')::uuid                   as category_id,
      nullif(r->>'name_en', '')                   as name_en,
      nullif(r->>'name_fr', '')                   as name_fr,
      nullif(r->>'name_ar', '')                   as name_ar,
      nullif(r->>'opening_hours_raw', '')         as opening_hours_raw,
      (r->>'avg_visit_duration_minutes')::int     as avg_visit_duration_minutes,
      (r->>'checkpoint_radius_meters')::int       as checkpoint_radius_meters,
      r->>'external_ref'                          as external_ref,
      (r->>'source')::poi_source                  as source,
      (r->>'status')::poi_status                  as status,
      st_setsrid(st_makepoint((r->>'lng')::double precision,
                              (r->>'lat')::double precision), 4326)::geography as location
    from jsonb_array_elements(p_rows) as r
  ),
  upserted as (
    insert into public.pois (
      city_id, category_id, name_en, name_fr, name_ar, location,
      opening_hours_raw, avg_visit_duration_minutes, checkpoint_radius_meters,
      external_ref, source, status
    )
    select
      city_id, category_id, name_en, name_fr, name_ar, location,
      opening_hours_raw, avg_visit_duration_minutes, checkpoint_radius_meters,
      external_ref, source, status
    from incoming
    on conflict (external_ref) where external_ref is not null
    do update set
      city_id                    = excluded.city_id,
      category_id                = excluded.category_id,
      name_en                    = excluded.name_en,
      name_fr                    = excluded.name_fr,
      name_ar                    = excluded.name_ar,
      location                   = excluded.location,
      opening_hours_raw          = excluded.opening_hours_raw,
      avg_visit_duration_minutes = excluded.avg_visit_duration_minutes,
      checkpoint_radius_meters   = excluded.checkpoint_radius_meters,
      status                     = excluded.status,
      deleted_at                 = null,
      updated_at                 = now()
    where pois.source = 'api_seeded'
      and pois.verified_by is null
    returning 1
  )
  select count(*) into v_written from upserted;

  return v_written;
end;
$$;

-- The unique index the conflict target needs. Partial, because external_ref is
-- nullable and several hand-authored rows legitimately have none.
create unique index if not exists uq_pois_external_ref
  on public.pois (external_ref) where external_ref is not null;

revoke execute on function public.upsert_ingested_pois(jsonb) from public, anon, authenticated;
grant execute on function public.upsert_ingested_pois(jsonb) to service_role;
