-- docs/backend/02 ("The radius query") + docs/backend/12 (score-floor filter).
-- security invoker keeps RLS applied — this is just a shaped, index-friendly
-- version of what "select ... from locations where is_active" already allows.
create or replace function public.nearby_locations(
  p_lat        double precision,
  p_lng        double precision,
  p_radius_km  double precision,
  p_categories text[] default null,
  p_min_score  numeric default 25,
  p_locale     text default 'en',
  p_limit      integer default 50
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
  order by l.is_curated desc, l.interest_score desc,
           l.geog <-> st_makepoint(p_lng, p_lat)::geography
  limit least(p_limit, 100);
$$;

grant execute on function public.nearby_locations(
  double precision, double precision, double precision, text[], numeric, text, integer
) to anon, authenticated;
