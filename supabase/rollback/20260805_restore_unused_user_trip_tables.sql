-- ---------------------------------------------------------------------
-- ROLLBACK SCRIPT — restores everything dropped by
-- supabase/migrations/20260805101612_drop_unused_user_trip_tables.sql
--
-- Captured from the live schema of project csrmogytbbjkbjmgedgx on
-- 2026-08-05, immediately before the drop. All five tables held 0 rows
-- and public.artifacts.trip_id was NULL on all 11 rows, so this restores
-- the schema exactly; there is no data to restore.
--
-- Run as a single transaction against the same project.
-- ---------------------------------------------------------------------

begin;

-- ---------------------------------------------------------------------
-- Enum (only trip_stops.task_state used it)
-- ---------------------------------------------------------------------
create type public.task_state as enum ('pending', 'active', 'done', 'skipped');

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------
create table public.trips (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  title            text,
  prompt           text,
  center           geography(Point, 4326),
  radius_km        double precision not null default 5,
  wanted_visits    smallint,
  selected_regions text[] not null default '{}',
  start_date       date,
  end_date         date,
  status           text not null default 'draft'
                   check (status in ('draft','active','completed','abandoned')),
  current_stop_idx smallint not null default 0,
  regenerations_left smallint not null default 3,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index trips_user_status_idx on public.trips (user_id, status, updated_at desc);
create unique index trips_one_active_per_user
  on public.trips (user_id) where status = 'active';


create table public.trip_stops (
  id             uuid primary key default gen_random_uuid(),
  trip_id        uuid not null references public.trips(id) on delete cascade,
  location_id    text not null references public.locations(id),
  position       integer not null,
  task_id        uuid references public.location_tasks(id),
  task_state     public.task_state not null default 'pending',
  points_awarded smallint not null default 0,
  completed_at   timestamptz,
  unique (trip_id, location_id),
  unique (trip_id, position) deferrable initially deferred
);

create index trip_stops_trip_idx on public.trip_stops (trip_id, position);


create table public.swipe_decisions (
  user_id     uuid not null references auth.users(id) on delete cascade,
  location_id text not null references public.locations(id),
  trip_id     uuid references public.trips(id) on delete set null,
  accepted    boolean not null,
  decided_at  timestamptz not null default now(),
  primary key (user_id, location_id, trip_id)
);


create table public.saved_locations (
  user_id     uuid not null references auth.users(id) on delete cascade,
  location_id text not null references public.locations(id) on delete cascade,
  saved_at    timestamptz not null default now(),
  primary key (user_id, location_id)
);


create table public.chat_messages (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  thread_kind text not null check (thread_kind in ('location','trip')),
  location_id text references public.locations(id) on delete cascade,
  trip_id     uuid references public.trips(id) on delete cascade,
  role        text not null check (role in ('user','assistant','system')),
  content     text not null,
  tokens_in   integer,
  tokens_out  integer,
  created_at  timestamptz not null default now()
);

create index chat_thread_idx
  on public.chat_messages (user_id, thread_kind, coalesce(location_id, trip_id::text), created_at);

-- ---------------------------------------------------------------------
-- artifacts.trip_id (was all-NULL, dropped with the trips table)
-- ---------------------------------------------------------------------
alter table public.artifacts
  add column trip_id uuid references public.trips(id) on delete set null;

-- ---------------------------------------------------------------------
-- Triggers / functions
-- ---------------------------------------------------------------------
create or replace function public.sync_total_points()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  update public.profiles p
     set total_points = (
       select coalesce(sum(ts.points_awarded), 0)
       from public.trip_stops ts
       join public.trips t on t.id = ts.trip_id
       where t.user_id = p.id and ts.task_state = 'done'
     )
   where p.id = (select user_id from public.trips where id = new.trip_id);
  return new;
end;
$function$;

create trigger t_stop_points
  after update of task_state on public.trip_stops
  for each row when (new.task_state = 'done')
  execute function public.sync_total_points();

create trigger t_trips_touch
  before update on public.trips
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table public.trips           enable row level security;
alter table public.trip_stops      enable row level security;
alter table public.saved_locations enable row level security;
alter table public.chat_messages   enable row level security;
alter table public.swipe_decisions enable row level security;

create policy "own trips" on public.trips
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "own trip stops" on public.trip_stops
  for all to authenticated
  using (exists (
    select 1 from public.trips t
    where t.id = trip_stops.trip_id and t.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.trips t
    where t.id = trip_stops.trip_id and t.user_id = (select auth.uid())
  ));

create policy "own saved locations" on public.saved_locations
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "own chat messages" on public.chat_messages
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "own swipe decisions" on public.swipe_decisions
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- Grants (matching the Supabase defaults these tables had)
-- ---------------------------------------------------------------------
grant all on public.trips, public.trip_stops, public.swipe_decisions,
             public.saved_locations, public.chat_messages
  to anon, authenticated, service_role, postgres;

commit;
