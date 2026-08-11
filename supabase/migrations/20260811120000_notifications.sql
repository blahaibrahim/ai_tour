-- ---------------------------------------------------------------------
-- Notifications: device push tokens, per-user preferences, send log, and
-- the model_jobs completion hook.
--
-- Three notification triggers exist in the app (docs/backend/15):
--
--   1. Route ready          — client-side local notification. Route generation
--                             is a synchronous call the *client* holds, so the
--                             server never learns it finished; nothing here.
--   2. 3D generation done   — genuinely server-originated. The trigger at the
--                             bottom of this file is what starts it.
--   3. Fennec proximity     — client-side local notification from an OS
--                             geofence / the live hunt stream. Deliberately not
--                             push (docs/mascot_plan.md §5.6), so nothing here.
--
-- `push_tokens` was specified in docs/mascot_plan.md §7 and referenced by
-- `backend/server-node/src/arCapture/data/pushTokenRepository.ts` from the day
-- that module landed, but no migration ever created it — every push token the
-- app registered went to a table that did not exist. This is that migration.
-- ---------------------------------------------------------------------

-- pg_net drives the model_jobs → backend webhook at the bottom of this file.
-- Guarded the same way pg_cron is in 20260801120005: on a Postgres without it,
-- everything else here still applies and only the hook is skipped.
create extension if not exists pg_net with schema extensions;


-- ---------------------------------------------------------------------
-- push_tokens — one row per device, per docs/mascot_plan.md §7
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'device_platform') then
    create type public.device_platform as enum ('android', 'ios', 'web');
  end if;
end
$$;

create table if not exists public.push_tokens (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  -- The FCM registration token. UNIQUE, not (user_id, token): a device that
  -- changes hands keeps its token and must move to the new user rather than
  -- deliver the previous one's notifications, which is exactly what the
  -- backend's `onConflict: "token"` upsert relies on.
  token         text not null unique,
  platform      public.device_platform not null,
  ar_capability text,                     -- 'full' | 'limited' | 'none' — telemetry
  last_seen_at  timestamptz not null default now()
);

create index if not exists idx_push_tokens_user on public.push_tokens (user_id);


-- ---------------------------------------------------------------------
-- notification_prefs — what "Notify me" actually toggles
--
-- One row per user, not per route: pressing "Notify me" on the thinking screen
-- once opts the traveller in for every route from then on, which is the whole
-- point of the affordance. A row's absence means "never asked" — distinct from
-- an explicit opt-out, so the prompt can keep showing until it is answered.
-- ---------------------------------------------------------------------
create table if not exists public.notification_prefs (
  user_id            uuid primary key references auth.users(id) on delete cascade,
  enabled            boolean not null default true,
  -- Mirrors the client's own policy and docs/mascot_plan.md §5.6's table.
  -- Local hours, 0-23; start = end means "never quiet".
  quiet_hours_start  smallint not null default 22,
  quiet_hours_end    smallint not null default 7,
  -- The device's offset from UTC, in minutes, refreshed whenever the app
  -- registers its push token. Without it "quiet hours" would be evaluated in
  -- the *server's* timezone, which is the difference between suppressing a
  -- 3 a.m. notification and sending one.
  utc_offset_minutes smallint not null default 0,
  -- Per-category opt-outs, so a traveller who wants "your model is ready" but
  -- not "a fennec is near" does not have to choose between all and nothing.
  route_ready        boolean not null default true,
  model_ready        boolean not null default true,
  mascot_nearby      boolean not null default true,
  updated_at         timestamptz not null default now(),
  constraint quiet_hours_start_range check (quiet_hours_start between 0 and 23),
  constraint quiet_hours_end_range   check (quiet_hours_end   between 0 and 23)
);


-- ---------------------------------------------------------------------
-- notification_log — what the cooldown and daily cap are computed from
--
-- `notificationPolicy.shouldNotify` (arCapture/domain) takes the log as an
-- argument rather than reading it; this is the table the caller reads it from.
-- `dedupe_key` is the subject of the notification — a spawn id for a proximity
-- alert, a job id for a 3D completion — and is what stops the same event
-- notifying twice when a retry or a second writer re-fires the hook.
-- ---------------------------------------------------------------------
create table if not exists public.notification_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  kind        text not null,              -- 'model_ready' | 'mascot_nearby' | ...
  dedupe_key  text,
  sent_at     timestamptz not null default now()
);

create index if not exists idx_notification_log_user_sent
  on public.notification_log (user_id, sent_at desc);

-- Only one notification per subject, ever. The 3D hook fires on every terminal
-- UPDATE of a row, and the stuck-job cron sweeper can write one after the
-- worker already did; without this the traveller gets the same "your model is
-- ready" twice.
create unique index if not exists uq_notification_log_dedupe
  on public.notification_log (user_id, kind, dedupe_key)
  where dedupe_key is not null;


-- ---------------------------------------------------------------------
-- RLS
--
-- Push tokens are readable by their owner but written only by the backend:
-- the app registers through POST /api/devices/push-token, which holds the
-- service_role key, so `authenticated` needs no write path and giving it one
-- would let any session point another user's token at itself. The log is
-- server-only in both directions — it is bookkeeping for the send policy, not
-- an inbox.
-- ---------------------------------------------------------------------
alter table public.push_tokens        enable row level security;
alter table public.notification_prefs enable row level security;
alter table public.notification_log   enable row level security;

drop policy if exists "own push tokens readable" on public.push_tokens;
create policy "own push tokens readable" on public.push_tokens
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "own notification prefs" on public.notification_prefs;
create policy "own notification prefs" on public.notification_prefs
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- No policy on notification_log at all: RLS on with zero policies denies
-- everything to anon/authenticated, and service_role bypasses RLS.


-- ---------------------------------------------------------------------
-- Backend webhook configuration
--
-- The trigger below needs the backend's URL and a shared secret. Both are
-- deployment configuration, not code, so they live in a table rather than in
-- this file — set them once per environment with:
--
--   insert into private.app_settings (key, value) values
--     ('notify_hook_url',    'https://your-backend/api/internal/model-job-notify'),
--     ('notify_hook_secret', '<same value as NOTIFY_HOOK_SECRET in backend/.env>')
--   on conflict (key) do update set value = excluded.value;
--
-- The `private` schema is not exposed through PostgREST, so the secret is not
-- reachable from the app under any key.
-- ---------------------------------------------------------------------
create schema if not exists private;

create table if not exists private.app_settings (
  key   text primary key,
  value text not null
);

revoke all on private.app_settings from anon, authenticated;
revoke all on schema private from anon, authenticated;


-- ---------------------------------------------------------------------
-- model_jobs → backend notification hook
--
-- Fires on the transition *into* a terminal status, from any writer. That
-- "any writer" is the reason this is a database trigger rather than a call
-- bolted onto the Modal worker: three separate things write terminal states —
-- backend/hunyuan2.1/api.py on success and on generation failure,
-- routes/models.ts on submit failure, and the reconcile-stuck-jobs cron job
-- on timeout — and a notification the traveller only gets for one of those
-- three is worse than none, because it makes silence mean nothing.
--
-- pg_net's http_post is asynchronous: it queues the request and returns an
-- id immediately, so a slow or dead backend cannot hold the worker's UPDATE
-- open. A dropped notification is acceptable here; a blocked write is not.
-- ---------------------------------------------------------------------
create or replace function private.notify_model_job_terminal()
returns trigger
language plpgsql
security definer
set search_path = private, public, extensions, net
as $$
declare
  hook_url    text;
  hook_secret text;
begin
  select value into hook_url    from private.app_settings where key = 'notify_hook_url';
  select value into hook_secret from private.app_settings where key = 'notify_hook_secret';

  -- Unconfigured environment (local dev, CI): do nothing, quietly. The job
  -- itself still completes and the app's realtime subscription still updates
  -- the folder — push is the only thing missing.
  if hook_url is null or hook_secret is null then
    return null;
  end if;

  begin
    perform net.http_post(
      url     := hook_url,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'X-Notify-Secret', hook_secret
      ),
      body    := jsonb_build_object(
        'job_id',      new.id,
        'user_id',     new.user_id,
        'artifact_id', new.artifact_id,
        'status',      new.status,
        'error_code',  new.error_code,
        'output_path', new.output_path
      ),
      timeout_milliseconds := 5000
    );
  exception
    when others then
      -- Swallow pg_net exceptions (e.g. private network requests in dev)
      -- so the job update still commits and Realtime updates the app.
      null;
  end;

  return null;
end;
$$;

revoke all on function private.notify_model_job_terminal() from anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_net') then
    drop trigger if exists trg_model_jobs_notify on public.model_jobs;
    -- AFTER, so a failure here can never roll back the status write, and
    -- `distinct from` so re-writing the same terminal status (an idempotent
    -- worker retry) does not re-notify.
    create trigger trg_model_jobs_notify
      after update of status on public.model_jobs
      for each row
      when (
        new.status in ('succeeded', 'failed', 'cancelled')
        and old.status is distinct from new.status
      )
      execute function private.notify_model_job_terminal();
  end if;
end
$$;
