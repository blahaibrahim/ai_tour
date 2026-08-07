-- Realtime for model_jobs.
--
-- AppBloc._startRealtimeSubscription() subscribes to `model_jobs` and is the
-- only thing that moves an artifact out of the "Generating 3D…" badge. The
-- `supabase_realtime` publication was empty, so that stream never delivered a
-- row: even a job the Modal worker finished correctly left the folder spinning
-- until the app was restarted.
--
-- REPLICA IDENTITY FULL so the `.eq('user_id', ...)` filter on the stream has
-- a user_id to match against in UPDATE payloads (the default identity carries
-- only the primary key). The table is small and low-volume, so the extra WAL
-- is not a concern.

alter table public.model_jobs replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'model_jobs'
  ) then
    alter publication supabase_realtime add table public.model_jobs;
  end if;
end
$$;
