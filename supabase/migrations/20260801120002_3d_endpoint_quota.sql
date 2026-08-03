-- ---------------------------------------------------------------------
-- 3D Endpoint Quota & Refund RPCs
-- ---------------------------------------------------------------------

create or replace function public.consume_model_credit(p_user uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_ok boolean;
begin
  update public.profiles
     set model_credits = model_credits - 1,
         credits_reset_at = case
           when credits_reset_at < date_trunc('day', now())
           then now() else credits_reset_at end
   where id = p_user and model_credits > 0
  returning true into v_ok;

  return coalesce(v_ok, false);
end;
$$;

revoke execute on function public.consume_model_credit(uuid) from anon, authenticated;


create or replace function public.refund_model_credit(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
     set model_credits = model_credits + 1
   where id = p_user;
end;
$$;

revoke execute on function public.refund_model_credit(uuid) from anon, authenticated;


-- ---------------------------------------------------------------------
-- Daily Quota Top-up Cron
-- ---------------------------------------------------------------------

select cron.schedule('reset-credits', '0 0 * * *', $$
  update public.profiles
     set model_credits = case when id in (
           select id from auth.users where email is not null
         ) then 10 else 3 end,
         credits_reset_at = now();
$$);


-- ---------------------------------------------------------------------
-- Rate Limiting
-- ---------------------------------------------------------------------

create table public.rate_limit_events (
  user_id uuid not null,
  action  text not null,
  at      timestamptz not null default now()
);
create index rlk on public.rate_limit_events (user_id, action, at desc);

create or replace function public.check_rate_limit(
  p_user uuid, p_action text, p_max int, p_window interval
) returns boolean
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from public.rate_limit_events where at < now() - interval '1 day';
  select count(*) into n from public.rate_limit_events
   where user_id = p_user and action = p_action and at > now() - p_window;
  if n >= p_max then return false; end if;
  insert into public.rate_limit_events (user_id, action) values (p_user, p_action);
  return true;
end;
$$;
