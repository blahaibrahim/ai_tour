-- ---------------------------------------------------------------------
-- RLS for User Tables
-- ---------------------------------------------------------------------

alter table public.profiles        enable row level security;
alter table public.trips           enable row level security;
alter table public.trip_stops      enable row level security;
alter table public.saved_locations enable row level security;
alter table public.artifacts       enable row level security;
alter table public.model_jobs      enable row level security;
alter table public.chat_messages   enable row level security;
alter table public.swipe_decisions enable row level security;


-- ---------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------
create policy "own profile" on public.profiles
  for all to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- Revoke write access to sensitive columns
revoke update (model_credits, total_points) on public.profiles from authenticated;

-- ---------------------------------------------------------------------
-- trips
-- ---------------------------------------------------------------------
create policy "own trips" on public.trips
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- trip_stops
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- saved_locations
-- ---------------------------------------------------------------------
create policy "own saved locations" on public.saved_locations
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- artifacts
-- ---------------------------------------------------------------------
create policy "own artifacts" on public.artifacts
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- model_jobs
-- ---------------------------------------------------------------------
create policy "own model jobs" on public.model_jobs
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- chat_messages
-- ---------------------------------------------------------------------
create policy "own chat messages" on public.chat_messages
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- swipe_decisions
-- ---------------------------------------------------------------------
create policy "own swipe decisions" on public.swipe_decisions
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
