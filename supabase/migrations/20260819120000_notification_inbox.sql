-- ---------------------------------------------------------------------
-- The in-app notification inbox, and the `splat_ready` kind that made it
-- necessary.
--
-- 20260811120000 gave the app three notification triggers and no history:
-- `notification_log` is send-policy bookkeeping (server-only in both
-- directions, 24-hour reads, no copy), and a push notification that arrives
-- while the phone is face-down in a bag is gone the moment the tray is
-- swiped. Everything the traveller was told is therefore unrecoverable, which
-- is fine for "you're getting warm" and not fine for "your footage of the
-- Bardo became a 3D scene" — that one is a *thing to go and look at*, and it
-- needs a durable place to be tapped from.
--
-- So: `user_notifications` is the inbox. It is the traveller's, not the
-- server's — they read it, mark it read, delete a row, or empty it — while
-- `notification_log` stays exactly what it was. Two tables because they
-- answer two different questions: "may I send this?" and "what have I been
-- told?".
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- notification_prefs gains the fourth category
--
-- `splat_ready` is the notification a *contributor* gets when footage they
-- recorded is turned into a gaussian splat by the studio dashboard. It is
-- opt-outable on its own like the other three: it arrives days after the
-- capture and is the least expected of the four, so a traveller who wants
-- "your model is ready" and not this needs somewhere to say so.
--
-- `NotificationKind` in backend/server-node/src/notifications/types.ts is the
-- same four values, and the column name is the camelCase of the kind on
-- purpose — that correspondence is what keeps the enum, the opt-out column and
-- the log's `kind` from drifting apart.
-- ---------------------------------------------------------------------
alter table public.notification_prefs
  add column if not exists splat_ready boolean not null default true;


-- ---------------------------------------------------------------------
-- user_notifications — the inbox
-- ---------------------------------------------------------------------
create table if not exists public.user_notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  -- Same vocabulary as notification_log.kind. Deliberately text rather than an
  -- enum: a new kind should be one backend deploy, not a migration that has to
  -- land before the code that sends it.
  kind       text not null,
  -- The copy, stored rather than re-derived. A notification is a record of what
  -- the traveller was actually told; rebuilding the sentence from ids at read
  -- time would silently rewrite history whenever the wording changed.
  title      text not null,
  body       text not null,
  -- Everything the tap needs: `type` plus whichever ids that type routes on
  -- (`route_id`, `artifact_id`, `splat_path`…). Same shape as the FCM `data`
  -- block, so the deep-link switch in the app reads one map either way.
  data       jsonb not null default '{}'::jsonb,
  -- The subject of the notification, matching notification_log.dedupe_key. The
  -- unique index below is what stops a retried webhook filing the same event
  -- twice in the inbox.
  dedupe_key text,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

-- The one read the app does: newest first, this user only.
create index if not exists idx_user_notifications_user_created
  on public.user_notifications (user_id, created_at desc);

-- The unread badge, which is a count over a tiny fraction of the rows.
create index if not exists idx_user_notifications_unread
  on public.user_notifications (user_id)
  where read_at is null;

create unique index if not exists uq_user_notifications_dedupe
  on public.user_notifications (user_id, kind, dedupe_key)
  where dedupe_key is not null;


-- ---------------------------------------------------------------------
-- RLS
--
-- Read, mark-read and delete for the owner; no insert. An inbox the client can
-- write to is a client that can post itself a notification from the studio —
-- and since the only thing the app does with a row is *believe* it, that would
-- make every notification unverifiable. Writes come from the backend's
-- service_role, which bypasses RLS.
--
-- The update policy's `with check` repeats the `using` clause because they
-- guard different rows: `using` picks which rows may be updated, `with check`
-- validates the result, and without the second one a traveller could hand a
-- notification to somebody else by updating its `user_id`.
-- ---------------------------------------------------------------------
alter table public.user_notifications enable row level security;

drop policy if exists "own notifications readable" on public.user_notifications;
create policy "own notifications readable" on public.user_notifications
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "own notifications updatable" on public.user_notifications;
create policy "own notifications updatable" on public.user_notifications
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "own notifications deletable" on public.user_notifications;
create policy "own notifications deletable" on public.user_notifications
  for delete to authenticated
  using ((select auth.uid()) = user_id);


-- ---------------------------------------------------------------------
-- The `splats` bucket
--
-- A trained gaussian splat `.ply` out of the pipeline is hundreds of megabytes
-- (the Bardo run is 468 MB) — not something to hand a phone on a mobile
-- connection. The studio dashboard decimates one into a compact `.splatb`
-- (position, colour, radius, ~20 bytes per gaussian) before uploading, which
-- puts a viewable scene in single-digit megabytes. 32 MB is the ceiling so a
-- larger, more detailed decimation stays possible without another migration.
--
-- Not public, and not folder-scoped either — which makes it the first bucket
-- here that is neither. A splat is a *shared* object: it is built from footage
-- one traveller recorded at a POI everybody can visit, and the whole point of
-- the notification is to show it off. So any signed-in traveller may read the
-- bucket, and only service_role may write it. `(storage.foldername(name))[1]`
-- is the scene, not a user id.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('splats', 'splats', false, 33554432, array['application/octet-stream'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "read splats" on storage.objects;
create policy "read splats"
  on storage.objects for select to authenticated
  using (bucket_id = 'splats');
