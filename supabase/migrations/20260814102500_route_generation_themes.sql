-- Option B for the theme→category mapping: the vocabulary lives in the
-- database, not in TypeScript.
--
-- The app speaks in themes ("History", "Nature"); pois carry a category_id.
-- Nothing joined the two, so POISelector.categoriesForTheme had no source. A
-- table rather than a constant because adding or retuning a city must not
-- need a deploy — the same "config, not code" property cities.rollout_status
-- and cities.active_routing_provider already have (spec §2). It is also the
-- vocabulary the LLM prompt interpreter is constrained to, so the chips and
-- the model read one list and cannot drift apart.

create table if not exists public.themes (
    id         uuid primary key default gen_random_uuid(),
    key        text not null unique,
    label_en   text not null,
    label_fr   text not null,
    label_ar   text not null,
    sort_order integer not null default 0,
    is_active  boolean not null default true
);

-- city_id NULL means "applies in every city". A city only gets its own rows
-- when it actually differs — "Nature" in Algiers is beaches and coastal parks,
-- in Tamanrasset it is desert and oases with no beach at all.
create table if not exists public.theme_categories (
    id          uuid primary key default gen_random_uuid(),
    theme_id    uuid not null references public.themes(id) on delete cascade,
    category_id uuid not null references public.categories(id) on delete cascade,
    city_id     uuid references public.cities(id) on delete cascade
);

-- A plain PK cannot span a nullable column, and NULLS NOT DISTINCT is too new
-- to rely on, so the "one row per (theme, category, scope)" rule is expressed
-- with a coalesced unique index instead.
create unique index if not exists uq_theme_categories
    on public.theme_categories (
        theme_id, category_id, coalesce(city_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );
create index if not exists idx_theme_categories_lookup
    on public.theme_categories (theme_id, city_id);

alter table public.themes enable row level security;
alter table public.theme_categories enable row level security;

drop policy if exists themes_public on public.themes;
create policy themes_public on public.themes for select using (is_active);

drop policy if exists theme_categories_public on public.theme_categories;
create policy theme_categories_public on public.theme_categories for select using (true);

-- Resolution, in one place so the override rule cannot be reimplemented
-- differently by a caller: if a city has its own rows for this theme they
-- replace the global set entirely, otherwise the global set applies. Replace
-- rather than union — a city that overrides "nature" to mean desert must not
-- silently keep inheriting beaches.
create or replace function public.theme_category_keys(
    p_theme_key text,
    p_city_id   uuid default null
)
returns table (category_key text)
language sql
stable
security invoker
set search_path = public
as $$
  with t as (
    select id from public.themes where key = p_theme_key and is_active
  ),
  scoped as (
    select tc.category_id
    from public.theme_categories tc
    join t on t.id = tc.theme_id
    where p_city_id is not null and tc.city_id = p_city_id
  ),
  resolved as (
    select category_id from scoped
    union all
    select tc.category_id
    from public.theme_categories tc
    join t on t.id = tc.theme_id
    where tc.city_id is null
      and not exists (select 1 from scoped)
  )
  select distinct c.key
  from resolved r
  join public.categories c on c.id = r.category_id
  order by 1;
$$;

grant execute on function public.theme_category_keys(text, uuid)
  to anon, authenticated, service_role;

-- Only themes that can actually be fulfilled are listed.
--
-- A theme resolving to a category is not the same as that theme being
-- answerable: "nature" maps to beaches, but no city seeded so far has a beach
-- POI. Listing a theme whose categories hold no published POI in the requested
-- city means the traveller picks it and gets 422 no_eligible_pois — which
-- reads as "there is nothing here" rather than "we should not have offered
-- that". Requiring a real POI makes the empty-theme case unrepresentable
-- instead of remembered.
create or replace function public.themes_available(p_city_id uuid default null)
returns table (
    key      text,
    label_en text,
    label_fr text,
    label_ar text
)
language sql
stable
security invoker
set search_path = public
as $$
  select t.key, t.label_en, t.label_fr, t.label_ar
  from public.themes t
  where t.is_active
    and exists (
      select 1
      from public.theme_category_keys(t.key, p_city_id) k
      join public.categories c on c.key = k.category_key
      join public.pois p on p.category_id = c.id
      where p.status = 'published'
        and p.deleted_at is null
        and (p_city_id is null or p.city_id = p_city_id)
    )
  order by t.sort_order, t.key;
$$;

grant execute on function public.themes_available(uuid) to anon, authenticated, service_role;
