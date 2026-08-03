-- 1. Create Storage Buckets
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('captures',   'captures',   false, 10485760, array['image/jpeg','image/png','image/webp']),
  ('models',     'models',     false, 52428800, array['model/gltf-binary','application/octet-stream']),
  ('thumbnails', 'thumbnails', false,   524288, array['image/webp','image/jpeg']),
  ('catalogue',  'catalogue',  true,  5242880,  array['image/jpeg','image/webp'])
on conflict (id) do update set 
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Storage RLS Policies

-- Captures
create policy "read own captures"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'captures'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "write own captures"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'captures'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "delete own captures"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'captures'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Thumbnails
create policy "read own thumbnails"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "write own thumbnails"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "delete own thumbnails"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Models (Read-only for clients, written by Modal service role)
create policy "read own models"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'models'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "delete own models"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'models'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Catalogue (Public Read)
create policy "public read catalogue"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'catalogue');


-- 3. Anonymous Users Purge Function
create or replace function public.purge_anonymous_users(p_interval interval)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  stale_uid uuid;
begin
  for stale_uid in
    select id from auth.users
    where is_anonymous = true
      and updated_at < now() - p_interval
  loop
    -- Delete storage objects first
    delete from storage.objects where (storage.foldername(name))[1] = stale_uid::text;
    -- Delete from auth (cascades to public.profiles)
    delete from auth.users where id = stale_uid;
  end loop;
end;
$$;

-- 4. Orphan Storage Purge Function
create or replace function public.purge_orphan_storage_objects()
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  -- Delete captures and models that have no matching artifacts row
  delete from storage.objects o
  where o.bucket_id in ('captures', 'models')
    and not exists (
      select 1 from public.artifacts a 
      where a.user_id::text = (storage.foldername(o.name))[1]
        and (a.id::text = split_part(split_part(o.name, '/', 2), '.', 1) 
             or o.name like '%' || a.id::text || '.%')
    );
end;
$$;

-- 5. pg_cron Schedules (Ignore if pg_cron extension missing)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('purge-stale-anon', '0 3 * * *', 'select public.purge_anonymous_users(interval ''90 days'');');
    perform cron.schedule('purge-orphan-media', '0 4 * * *', 'select public.purge_orphan_storage_objects();');
    perform cron.schedule('reconcile-stuck-jobs', '*/5 * * * *', 'update public.model_jobs set status = ''failed'', error_code = ''timeout'', finished_at = now() where status in (''queued'',''processing'') and queued_at < now() - interval ''20 minutes'';');
  end if;
end
$$;
