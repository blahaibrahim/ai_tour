-- `uploadBinary(..., upsert: true)` performs an UPDATE when the object already
-- exists, and there was no UPDATE policy on storage.objects — only INSERT. So
-- the idempotent-retry behaviour the capture upload relies on would have been
-- refused the moment it was actually needed, which is the one moment nobody
-- tests. Same ownership predicate as the other three.
create policy "update own captures" on storage.objects
  for update to authenticated
  using (bucket_id = 'captures' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'captures' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "update own thumbnails" on storage.objects
  for update to authenticated
  using (bucket_id = 'thumbnails' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'thumbnails' and (storage.foldername(name))[1] = (select auth.uid())::text);
