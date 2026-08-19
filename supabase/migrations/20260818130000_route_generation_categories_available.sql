-- Grounding vocabulary for the LLM prompt interpreter.
--
-- `themes_available` (20260814102500) already answers "which themes can this
-- city route" so the chip picker never offers a theme worth a 422. The prompt
-- interpreter needs the same guarantee one level down: it may only hand back
-- a category key that provably has a published POI behind it in this city,
-- or a hallucinated key (or a real key with zero POIs here) turns "beaches
-- preferably" into a route that boosts nothing.
--
-- `p_theme_key` is optional and, when given, narrows to that theme's own
-- category set via `theme_category_keys` — the same per-city override rule
-- that function already encodes, not reimplemented here. Left null it
-- answers city-wide, which is what a not-yet-interpreted prompt needs.
--
-- `poi_count` travels with each row so the interpreter (and its prompt to the
-- model) can prefer the categories with more to show, and so a category that
-- clears the "has at least one POI" bar but is nearly empty doesn't read as
-- equally strong as one with dozens.
create or replace function public.categories_available(
    p_city_id   uuid,
    p_theme_key text default null
)
returns table (
    key       text,
    label_en  text,
    label_fr  text,
    label_ar  text,
    poi_count bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  select c.key, c.label_en, c.label_fr, c.label_ar, count(p.id) as poi_count
  from public.categories c
  join public.pois p on p.category_id = c.id
  where p.status = 'published'
    and p.deleted_at is null
    and p.city_id = p_city_id
    and (
      p_theme_key is null
      or c.key in (select k.category_key from public.theme_category_keys(p_theme_key, p_city_id) k)
    )
  group by c.key, c.label_en, c.label_fr, c.label_ar
  order by poi_count desc, c.key;
$$;

revoke all on function public.categories_available(uuid, text) from public, anon, authenticated;
grant execute on function public.categories_available(uuid, text) to anon, authenticated, service_role;
