-- ---------------------------------------------------------------------
-- ROLLBACK SCRIPT — reverts
-- supabase/migrations/20260817120000_rewards_and_redemptions.sql
--
-- That migration is mostly additive, and additive things are safe to leave
-- behind. The parts that are *not* additive, and are what this script exists
-- for, are three functions it replaced in place:
--
--   award_task_points   — signature and return type both changed
--   consume_model_credit — now spends a second bucket
--   refund_model_credit  — now refunds into that bucket
--
-- Run as a single transaction against the same project.
--
-- ⚠ Points already spent are not restored. `points_balance` was decremented by
-- every redemption, and this script drops the redemptions table that records
-- what each debit was for. Export it first if any real redemption has happened:
--
--     copy (select * from public.redemptions) to stdout with csv header;
-- ---------------------------------------------------------------------

begin;

-- ---------------------------------------------------------------------
-- 1. Spending, removed
-- ---------------------------------------------------------------------
-- Order matters. `redemption_json` takes `public.redemptions` as a parameter
-- type, so the table cannot be dropped while it exists — Postgres refuses with
-- "cannot drop table redemptions because other objects depend on it". Functions
-- first, then the tables, and `rewards` last because `redemptions` references
-- it.
drop function if exists public.spend_points(text, text);
drop function if exists public.redemption_json(public.redemptions);
drop table if exists public.redemptions;
drop table if exists public.rewards;

-- ---------------------------------------------------------------------
-- 2. award_task_points, back to the integer-returning four-argument form
-- ---------------------------------------------------------------------
drop function if exists public.award_task_points(
  text, text, text, text, double precision, double precision, double precision
);

create or replace function public.award_task_points(
  p_completion_key text,
  p_task_type text default 'unknown',
  p_route_id text default null,
  p_poi_id text default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_points integer;
  v_total integer;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if p_completion_key is null or length(trim(p_completion_key)) = 0 then
    raise exception 'completion_key is required' using errcode = '22023';
  end if;

  v_points := 30;

  insert into public.task_completions
    (user_id, completion_key, route_id, poi_id, task_type, points)
  values
    (v_user, p_completion_key, p_route_id, p_poi_id,
     coalesce(nullif(trim(p_task_type), ''), 'unknown'), v_points)
  on conflict (user_id, completion_key) do nothing;

  select total_points into v_total from public.profiles where id = v_user;
  return coalesce(v_total, 0);
end;
$$;

revoke all on function public.award_task_points(text, text, text, text) from public, anon;
grant execute on function public.award_task_points(text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. The counter trigger, back to one column
-- ---------------------------------------------------------------------
create or replace function public.apply_task_completion_points()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  update public.profiles
     set total_points = total_points + new.points,
         updated_at = now()
   where id = new.user_id;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Model credits, back to one bucket
-- ---------------------------------------------------------------------
-- Anything sitting in model_credits_purchased is folded into the daily column
-- before it is dropped, so nobody loses a generation they paid for. The cron
-- will overwrite it at midnight, which is the behaviour this restores.
update public.profiles
   set model_credits = least(model_credits + model_credits_purchased, 32767)
 where model_credits_purchased > 0;

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

revoke execute on function public.consume_model_credit(uuid) from anon, authenticated;
revoke execute on function public.refund_model_credit(uuid) from anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Columns
-- ---------------------------------------------------------------------
alter table public.profiles drop column if exists points_balance;
alter table public.profiles drop column if exists model_credits_purchased;
alter table public.task_completions drop column if exists verification;
alter table public.task_completions drop column if exists spendable;

commit;
