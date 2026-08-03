-- ---------------------------------------------------------------------
-- Auth Profile Trigger
-- ---------------------------------------------------------------------
create extension if not exists pg_cron;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, locale)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', 'Explorer'),
    coalesce(new.raw_user_meta_data->>'locale', 'en')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ---------------------------------------------------------------------
-- Points Sync Trigger
-- ---------------------------------------------------------------------

create or replace function public.sync_total_points()
returns trigger 
language plpgsql 
security definer set search_path = '' 
as $$
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
$$;

create trigger t_stop_points after update of task_state on public.trip_stops
  for each row when (new.task_state = 'done')
  execute function public.sync_total_points();

-- ---------------------------------------------------------------------
-- Updated_at Triggers for new tables
-- ---------------------------------------------------------------------

create trigger t_profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

create trigger t_trips_touch before update on public.trips
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- Stale Anon Purge Cron
-- ---------------------------------------------------------------------

create or replace function public.purge_anonymous_users(p_interval interval)
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  -- Note: Storage object deletion would usually happen here or via Edge Function
  -- before deleting the auth user. Since this is just the DB layer:
  delete from auth.users 
  where is_anonymous = true 
    and created_at < now() - p_interval
    and not exists (
      select 1 from public.model_jobs where user_id = auth.users.id
    );
end;
$$;

select cron.schedule('purge-stale-anon', '0 3 * * *', $$
  select public.purge_anonymous_users(interval '90 days');
$$);
