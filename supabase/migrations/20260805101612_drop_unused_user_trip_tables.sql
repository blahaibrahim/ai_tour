-- Drop the five empty, entirely unreferenced user-scoped tables.
-- Rollback: supabase/rollback/20260805_restore_unused_user_trip_tables.sql
--
-- Kept deliberately: location_tasks and location_task_translations are also
-- empty, but the backend embeds them in its locations query
-- (backend/server/data/locations_repo.py) and the latter is a translation table.

drop trigger if exists t_stop_points on public.trip_stops;
drop function if exists public.sync_total_points();

-- All 11 artifacts rows had trip_id = null; no code reads or writes it.
alter table public.artifacts drop constraint if exists artifacts_trip_id_fkey;
alter table public.artifacts drop column if exists trip_id;

drop table if exists public.chat_messages;
drop table if exists public.swipe_decisions;
drop table if exists public.trip_stops;
drop table if exists public.saved_locations;
drop table if exists public.trips;

-- task_state was used only by trip_stops.task_state
drop type if exists public.task_state;
