-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------
create type public.task_state  as enum ('pending', 'active', 'done', 'skipped');
create type public.artifact_kind as enum ('photo', 'video', 'fennec', 'model');
create type public.job_status  as enum ('queued', 'uploading', 'processing', 'succeeded', 'failed', 'cancelled');

-- ---------------------------------------------------------------------
-- User-scoped tables
-- ---------------------------------------------------------------------

create table public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  display_name   text not null default 'Explorer',
  locale         text not null default 'en',
  theme_mode     text not null default 'system'
                 check (theme_mode in ('system','light','dark')),
  units_metric   boolean not null default true,
  total_points   integer not null default 0,
  model_credits  smallint not null default 5,
  credits_reset_at timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

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
  id           uuid primary key default gen_random_uuid(),
  trip_id      uuid not null references public.trips(id) on delete cascade,
  location_id  text not null references public.locations(id),
  position     integer not null,
  task_id      uuid references public.location_tasks(id),
  task_state   public.task_state not null default 'pending',
  points_awarded smallint not null default 0,
  completed_at timestamptz,
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

-- Note: model_jobs references artifacts, and artifacts references model_jobs (mutually recursive logically, but we use constraints)
-- Let's create artifacts without model_job_id foreign key first, then add it later, or create model_jobs without artifact_id first.
-- We will create model_jobs first without artifact_id, then artifacts, then add the constraint to model_jobs.

create table public.model_jobs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  -- artifact_id added below
  status          public.job_status not null default 'queued',
  input_path      text not null,
  input_sha256    text not null,
  output_path     text,
  modal_call_id   text,
  error_code      text,
  attempts        smallint not null default 0,
  queued_at       timestamptz not null default now(),
  started_at      timestamptz,
  finished_at     timestamptz,
  gpu_seconds     numeric(10,2)
);

create table public.artifacts (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  trip_id        uuid references public.trips(id) on delete set null,
  location_id    text references public.locations(id) on delete set null,
  kind           public.artifact_kind not null,
  title          text,
  image_path     text,
  model_path     text,
  model_job_id   uuid references public.model_jobs(id) on delete set null,
  captured_at    timestamptz not null default now(),
  deleted_at     timestamptz,
  local_id       text
);

alter table public.model_jobs add column artifact_id uuid references public.artifacts(id) on delete cascade;

create index artifacts_user_idx on public.artifacts (user_id, captured_at desc)
  where deleted_at is null;
create unique index artifacts_local_id_idx on public.artifacts (user_id, local_id)
  where local_id is not null;

create index model_jobs_user_idx   on public.model_jobs (user_id, queued_at desc);
create index model_jobs_status_idx on public.model_jobs (status)
  where status in ('queued','processing');
create index model_jobs_sha_idx    on public.model_jobs (input_sha256)
  where status = 'succeeded';


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
