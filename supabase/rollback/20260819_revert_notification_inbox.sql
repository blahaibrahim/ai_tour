-- Reverts 20260819120000_notification_inbox.sql.
--
-- Drops the inbox, the fourth opt-out column and the shared splat bucket. The
-- bucket's objects go with it: `storage.objects` has an FK to `storage.buckets`
-- and Storage refuses to drop a non-empty bucket, so the delete is explicit
-- and comes first. That is a real data loss — a decimated splat is
-- reproducible from the Volume copy, which is why it is acceptable here.
delete from storage.objects where bucket_id = 'splats';
drop policy if exists "read splats" on storage.objects;
delete from storage.buckets where id = 'splats';

drop table if exists public.user_notifications;

alter table public.notification_prefs drop column if exists splat_ready;
