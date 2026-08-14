-- `cities.bounding_box` is geography(POLYGON) and CityConfig.centre is its
-- centroid — the same PostgREST/PostGIS problem as pois.location, so the city
-- config read needs the same treatment. Everything else on the row is plain
-- scalars, but the centre is what the app centres its map on.
create or replace function public.cities_config(p_city_id uuid default null)
returns table (
  id                      uuid,
  region_id               uuid,
  name                    text,
  name_fr                 text,
  name_ar                 text,
  centre_lat              double precision,
  centre_lng              double precision,
  cluster_radius_meters   integer,
  active_routing_provider text,
  rollout_status          text,
  feature_flags           jsonb
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select
    c.id, c.region_id, c.name, c.name_fr, c.name_ar,
    st_y(st_centroid(c.bounding_box::geometry)),
    st_x(st_centroid(c.bounding_box::geometry)),
    c.cluster_radius_meters,
    c.active_routing_provider::text,
    c.rollout_status::text,
    c.feature_flags
  from public.cities c
  where c.deleted_at is null
    and (p_city_id is null or c.id = p_city_id)
  order by c.name;
$$;

grant execute on function public.cities_config(uuid) to anon, authenticated, service_role;

-- `findLatestForUser` ("resume my tour") filters on user_id and takes the
-- newest row; without this it is a sequential scan over every route ever
-- generated, which grows monotonically because routes are immutable.
create index if not exists idx_routes_user_generated
  on public.routes (user_id, generated_at desc)
  where user_id is not null;

-- progress.route_id carries a foreign key but no index, and
-- ProgressRepository.findByRouteId looks up by exactly that column.
create index if not exists idx_progress_route on public.progress (route_id);

-- A route's stop order is its identity — two stops claiming sequence 3 is a
-- corrupt route, and the assembler produces the ordering in one pass so this
-- can only ever fire on a genuine bug.
create unique index if not exists uq_route_stops_sequence
  on public.route_stops (route_id, sequence_order);
