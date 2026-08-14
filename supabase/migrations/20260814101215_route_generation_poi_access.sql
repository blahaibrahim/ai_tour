-- Route generation: PostgREST-safe access to the PostGIS POI rows.
--
-- `pois.location` is geography(POINT,4326). supabase-js selecting it directly
-- gets hex EWKB, not coordinates — the reference implementation dodges this
-- with Kysely raw SQL (ST_Y/ST_X), which PostgREST has no equivalent for.
-- Same shape as public.nearby_locations: an RPC that projects lat/lng as
-- doubles, security invoker so the pois_published RLS policy still applies.

create or replace function public.pois_eligible(
  p_city_id        uuid,
  p_category_keys  text[] default null,
  p_limit          integer default 200
)
returns table (
  id                          uuid,
  city_id                     uuid,
  category_id                 uuid,
  category_key                text,
  name_en                     text,
  name_fr                     text,
  name_ar                     text,
  description_en              text,
  description_fr              text,
  description_ar              text,
  lat                         double precision,
  lng                         double precision,
  opening_hours_raw           text,
  avg_visit_duration_minutes  integer,
  checkpoint_radius_meters    integer,
  ar_content_id               uuid,
  stamp_id                    uuid,
  external_ref                text,
  source                      text,
  status                      text,
  photo_url                   text,
  photo_attribution           text,
  photo_license               text,
  photo_source_url            text
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select
    p.id,
    p.city_id,
    p.category_id,
    c.key,
    p.name_en, p.name_fr, p.name_ar,
    p.description_en, p.description_fr, p.description_ar,
    st_y(p.location::geometry),
    st_x(p.location::geometry),
    p.opening_hours_raw,
    p.avg_visit_duration_minutes,
    p.checkpoint_radius_meters,
    p.ar_content_id,
    p.stamp_id,
    p.external_ref,
    p.source::text,
    p.status::text,
    p.photo_url, p.photo_attribution, p.photo_license, p.photo_source_url
  from public.pois p
  join public.categories c on c.id = p.category_id
  -- Stated explicitly rather than left to the RLS policy: the eligibility
  -- rule belongs to the query, and service_role bypasses RLS entirely.
  where p.status = 'published'
    and p.deleted_at is null
    and p.city_id = p_city_id
    and (p_category_keys is null or c.key = any(p_category_keys))
  order by p.id
  limit least(coalesce(p_limit, 200), 500);
$$;

grant execute on function public.pois_eligible(uuid, text[], integer)
  to anon, authenticated, service_role;

-- Rehydrating a saved route: route_stops joined back onto pois for the
-- coordinates and checkpoint radii. route_stops deliberately grants nothing
-- to anon/authenticated (see its table comment), so this is service_role only
-- and the server calls it with the admin client.
create or replace function public.route_stops_expanded(p_route_id uuid)
returns table (
  poi_id                      uuid,
  sequence_order              integer,
  cluster_id                  integer,
  category_key                text,
  name_en                     text,
  name_fr                     text,
  name_ar                     text,
  description_en              text,
  description_fr              text,
  description_ar              text,
  lat                         double precision,
  lng                         double precision,
  avg_visit_duration_minutes  integer,
  checkpoint_radius_meters    integer,
  opening_hours_raw           text,
  ar_content_id               uuid,
  stamp_id                    uuid,
  photo_url                   text,
  photo_attribution           text,
  photo_license               text,
  photo_source_url            text
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select
    rs.poi_id, rs.sequence_order, rs.cluster_id,
    c.key,
    p.name_en, p.name_fr, p.name_ar,
    p.description_en, p.description_fr, p.description_ar,
    st_y(p.location::geometry),
    st_x(p.location::geometry),
    p.avg_visit_duration_minutes,
    p.checkpoint_radius_meters,
    p.opening_hours_raw,
    p.ar_content_id, p.stamp_id,
    p.photo_url, p.photo_attribution, p.photo_license, p.photo_source_url
  from public.route_stops rs
  join public.pois p on p.id = rs.poi_id
  join public.categories c on c.id = p.category_id
  where rs.route_id = p_route_id
  order by rs.sequence_order;
$$;

revoke execute on function public.route_stops_expanded(uuid) from public, anon, authenticated;
grant execute on function public.route_stops_expanded(uuid) to service_role;
