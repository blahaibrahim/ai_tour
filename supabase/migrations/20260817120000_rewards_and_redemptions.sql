-- Points become spendable.
--
-- Until now `profiles.total_points` was a score and nothing more: the ledger in
-- `task_completions` only ever grew, and the onboarding's fourth slide — "turn
-- your points into something real" — was a promise with no mechanism behind it.
-- This migration adds the other half: a catalogue, a debit ledger, and the one
-- function permitted to move points out of a wallet.
--
-- Three decisions shape everything below.
--
-- 1. **Lifetime and balance are different numbers.** `total_points` stays what
--    it has always been — everything ever earned, the figure a rank or a level
--    would be computed from. Spending must not touch it, or a traveller drops a
--    level every time they redeem. `points_balance` is the wallet, and it is a
--    separate counter rather than `total_points - spent` because not every
--    earned point is spendable (see 2).
--
-- 2. **A task completed from the sofa cannot buy a real object.** Mascot
--    captures were already validated server-side — signed token, nonce, position
--    check — but photo and video tasks award on capture with nothing checked. A
--    catalogue containing physical goods turns that into a way to farm objects.
--    `award_task_points` now takes the fix the phone had at the moment of
--    completion and checks it against the POI's own `checkpoint_radius_meters`.
--    An unverified completion still counts toward the score and the walk; it
--    just does not reach the wallet.
--
-- 3. **Spending is not idempotent the way earning is.** Earning replays safely
--    because a duplicate hits a unique constraint and is discarded. A duplicate
--    *spend* discarded the same way would be correct, which is why redemptions
--    carry an idempotency key too — but the client must never queue one offline.
--    Two offline redemptions against one balance is an overdraft that cannot be
--    clawed back once the reward is in a hand.

-- ---------------------------------------------------------------------------
-- 1. The wallet
-- ---------------------------------------------------------------------------

-- The column and its backfill are one unit, and the backfill runs only on the
-- pass that creates the column.
--
-- That guard is the whole point of the DO block. The backfill is
-- `points_balance = total_points where points_balance = 0`, which is correct
-- exactly once: run it a second time, after people have spent down to zero, and
-- it refills every emptied wallet to its owner's lifetime score. Every other
-- statement in this migration is written to be re-runnable, and a hand-applied
-- migration eventually does get applied twice, so this one is not allowed to be
-- the exception.
do $$
declare
  v_fresh boolean := not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'profiles'
       and column_name = 'points_balance'
  );
begin
  if v_fresh then
    alter table public.profiles
      add column points_balance integer not null default 0
        check (points_balance >= 0);

    -- Everyone who earned points before this migration keeps them as balance.
    -- Retroactively withholding the unverified ones would be punishing
    -- travellers for a check that did not exist when they walked.
    update public.profiles set points_balance = total_points;
  end if;
end $$;

comment on column public.profiles.points_balance is
  'Spendable points. Separate from total_points, which is lifetime earned and never decreases. Written only by award_task_points and spend_points.';

-- The second wallet, added here so every new column on `profiles` lands in one
-- place. What it is for is explained where it is used, in §7.
alter table public.profiles
  add column if not exists model_credits_purchased integer not null default 0
    check (model_credits_purchased >= 0);

comment on column public.profiles.model_credits_purchased is
  'Generations bought with points. Never touched by the reset-credits cron, and spent only after the daily allowance in model_credits is exhausted.';

-- The wallet is as far out of the client's reach as the score. The grant on
-- profiles was already narrowed to the four presentational columns in migration
-- 20260812130000; this column is simply not among them, so nothing to revoke.

-- ---------------------------------------------------------------------------
-- 2. Verification on the earning side
-- ---------------------------------------------------------------------------

-- Three states, not two. "Unverifiable" is its own answer and it is the common
-- one in development: the app still runs demo routes whose POI ids exist in no
-- table, and a route generated in fixture mode carries the same. Treating those
-- as failures would zero the wallet of every developer and every traveller in a
-- city that has not been ingested yet, so they are trusted — the check is a
-- guard against a known POI being answered from the wrong place, not a
-- requirement that every place be known.
alter table public.task_completions
  add column if not exists verification text not null default 'unverifiable'
    check (verification in ('verified', 'unverified', 'unverifiable'));

alter table public.task_completions
  add column if not exists spendable boolean not null default true;

comment on column public.task_completions.verification is
  'verified = a GPS fix landed inside the POI checkpoint radius; unverified = the POI is known and the fix did not (or was absent); unverifiable = the POI is not in the catalogue, so there was nothing to check against.';

-- The counter trigger now maintains both columns. `spendable` is decided by
-- award_task_points and stored on the row, so the trigger stays a dumb sum and
-- the rule lives in exactly one place.
create or replace function public.apply_task_completion_points()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  update public.profiles
     set total_points   = total_points + new.points,
         points_balance = points_balance + case when new.spendable then new.points else 0 end,
         updated_at     = now()
   where id = new.user_id;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. award_task_points, with a position to check
-- ---------------------------------------------------------------------------
-- Dropped and recreated rather than replaced: the return type changes from
-- integer to jsonb. The caller now needs two numbers back — a score and a
-- wallet — and returning one and making it fetch the other would leave a window
-- where the screen shows a balance that has already moved.
--
-- The three new parameters carry defaults, so a build of the app from before
-- this migration keeps working: it sends no fix, its completions land as
-- 'unverified' against a known POI, and the traveller earns score but not
-- balance until they update. That is the correct failure direction.
drop function if exists public.award_task_points(text, text, text, text);

create or replace function public.award_task_points(
  p_completion_key text,
  p_task_type text default 'unknown',
  p_route_id text default null,
  p_poi_id text default null,
  p_lat double precision default null,
  p_lng double precision default null,
  p_accuracy_m double precision default null
)
returns jsonb
language plpgsql
security definer
-- Empty rather than the `public, extensions` this repo uses for its read-only
-- geo RPCs. This one writes a balance that buys real objects, so PostGIS is
-- reached by explicit schema qualification below instead of by search path.
set search_path = ''
as $$
declare
  v_user      uuid := (select auth.uid());
  v_points    integer;
  v_poi       uuid;
  v_poi_loc   extensions.geography;
  v_radius    integer;
  v_slack     double precision;
  v_state     text;
  v_spendable boolean;
  v_result    record;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if p_completion_key is null or length(trim(p_completion_key)) = 0 then
    raise exception 'completion_key is required' using errcode = '22023';
  end if;

  -- The award is still decided here and never by the caller.
  v_points := 30;

  -- `poi_id` is text with no foreign key (see the table's own comment), so it
  -- may be a uuid, a demo id, or nothing at all. Only the first can be checked.
  begin
    v_poi := p_poi_id::uuid;
  exception when others then
    v_poi := null;
  end;

  if v_poi is not null then
    select p.location, p.checkpoint_radius_meters
      into v_poi_loc, v_radius
      from public.pois p
     where p.id = v_poi;
  end if;

  if v_poi_loc is null then
    v_state := 'unverifiable';
  elsif p_lat is null or p_lng is null then
    v_state := 'unverified';
  else
    -- A poor fix should not cost the traveller their points, but a client must
    -- not be able to pass from anywhere by claiming a kilometre of error. The
    -- reported accuracy widens the radius, capped at 50 m.
    v_slack := least(greatest(coalesce(p_accuracy_m, 0), 0), 50);
    if extensions.st_dwithin(
         v_poi_loc,
         extensions.st_setsrid(
           extensions.st_makepoint(p_lng, p_lat), 4326
         )::extensions.geography,
         coalesce(v_radius, 40) + v_slack
       )
    then
      v_state := 'verified';
    else
      v_state := 'unverified';
    end if;
  end if;

  -- A completion that could not be placed still counts toward the walk and the
  -- score. It is worth a third of a verified one, and it does not reach the
  -- wallet — enough that finishing a task is never pointless, not enough to be
  -- worth farming.
  v_spendable := v_state <> 'unverified';
  if not v_spendable then
    v_points := 10;
  end if;

  insert into public.task_completions
    (user_id, completion_key, route_id, poi_id, task_type, points,
     verification, spendable)
  values
    -- `p_poi_id` verbatim, not the parsed uuid: a demo route's stop id is not
    -- one, and storing null for it would throw away the only record of which
    -- place the traveller was actually at.
    (v_user, p_completion_key, p_route_id, p_poi_id,
     coalesce(nullif(trim(p_task_type), ''), 'unknown'), v_points,
     v_state, v_spendable)
  on conflict (user_id, completion_key) do nothing;

  -- Read back after the trigger has run, and read back unconditionally: on a
  -- duplicate nothing was inserted and nothing moved, and the caller still ends
  -- up holding the authoritative pair rather than inferring either by adding.
  select pr.total_points, pr.points_balance
    into v_result
    from public.profiles pr
   where pr.id = v_user;

  return jsonb_build_object(
    'total_points',   coalesce(v_result.total_points, 0),
    'points_balance', coalesce(v_result.points_balance, 0),
    'verification',   v_state,
    'awarded',        v_points
  );
end;
$$;

revoke all on function public.award_task_points(
  text, text, text, text, double precision, double precision, double precision
) from public, anon;
grant execute on function public.award_task_points(
  text, text, text, text, double precision, double precision, double precision
) to authenticated;

comment on function public.award_task_points(
  text, text, text, text, double precision, double precision, double precision
) is
  'The only way to earn points. Decides the award and the verification state server-side, is idempotent on (user, completion_key), and returns the caller''s lifetime total and spendable balance.';

-- ---------------------------------------------------------------------------
-- 4. The catalogue
-- ---------------------------------------------------------------------------

create table if not exists public.rewards (
  -- A readable string, not a uuid. These ids are referenced by name in code
  -- (`model_credit` is fulfilled by incrementing a column) and read in logs.
  id text primary key,

  title text not null,
  blurb text not null,

  -- What it costs *us*, which is what decides how it is gated:
  --   digital  — an entitlement or a credit; near-zero marginal cost
  --   partner  — funded by a partner, so free to us and worth signing them for
  --   physical — a real object with a real price, so it needs a real account
  kind text not null check (kind in ('digital', 'partner', 'physical')),

  cost_points integer not null check (cost_points > 0),

  -- How the traveller actually receives it. `instant` is applied by
  -- spend_points itself; `voucher` mints a code for a partner to scan, which is
  -- the next stage of this work and is why the column exists now rather than in
  -- the migration that adds the scanning tool.
  fulfillment text not null default 'instant'
    check (fulfillment in ('instant', 'voucher')),

  -- What a reward actually *does*, expressed as data rather than as a branch
  -- on the id somewhere in the app. `spend_points` applies the credits itself;
  -- the rerolls are tour state that lives only on the device, so the client
  -- applies those — but it reads how many from here either way, and neither
  -- side has a list of reward ids compiled into it.
  grant_model_credits smallint not null default 0
    check (grant_model_credits >= 0),
  grant_quest_rerolls smallint not null default 0
    check (grant_quest_rerolls >= 0),

  -- False means it can be bought once and then owned. A redemption row is the
  -- entitlement — "do I have the desert fennec?" is "is there a redemption of
  -- it against my id" — so cosmetics need no second table to live in.
  repeatable boolean not null default false,

  -- Null is unlimited. A number is decremented under the same lock as the
  -- balance, so the last one cannot be sold twice.
  stock integer check (stock is null or stock >= 0),

  -- Where a physical reward is collected. Null for anything digital.
  pickup_note text,

  sort_order smallint not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.rewards enable row level security;

-- The catalogue is public to anyone signed in, including anonymously — a guest
-- should be able to see what their points are for before deciding whether to
-- make an account. Only the active rows: an item pulled from sale should
-- disappear from the screen without being deleted from the history that
-- references it.
drop policy if exists "active rewards are readable" on public.rewards;
create policy "active rewards are readable" on public.rewards
  for select to authenticated
  using (active);

grant select on public.rewards to authenticated;
revoke insert, update, delete, truncate on public.rewards from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. The debit ledger
-- ---------------------------------------------------------------------------

create table if not exists public.redemptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,

  reward_id text not null references public.rewards (id),

  -- Copied, not joined. What a reward costs today is not what it cost when it
  -- was bought, and a ledger that changes retroactively when the catalogue is
  -- repriced is not a ledger.
  cost_points integer not null check (cost_points >= 0),

  -- Same lesson as task_completions: the app's whole culture is retry-friendly,
  -- so the write has to absorb a replay rather than trust it will not happen.
  idempotency_key text not null,

  -- Short, unambiguous, and readable aloud at a counter. Null for anything
  -- fulfilled instantly — there is nothing to present.
  code text unique,

  status text not null default 'fulfilled'
    check (status in ('fulfilled', 'issued', 'redeemed', 'expired')),

  -- Only meaningful for vouchers.
  expires_at timestamptz,
  redeemed_at timestamptz,

  created_at timestamptz not null default now(),

  constraint redemptions_key_unique unique (user_id, idempotency_key)
);

create index if not exists redemptions_user_created_idx
  on public.redemptions (user_id, created_at desc);

-- Answers "does this traveller already own that?" without scanning history.
create index if not exists redemptions_user_reward_idx
  on public.redemptions (user_id, reward_id);

alter table public.redemptions enable row level security;

-- Read only, and only your own. There is deliberately no insert, update or
-- delete policy: the sole writer is spend_points, which is SECURITY DEFINER and
-- therefore not subject to these at all.
drop policy if exists "own redemptions read" on public.redemptions;
create policy "own redemptions read" on public.redemptions
  for select to authenticated
  using ((select auth.uid()) = user_id);

grant select on public.redemptions to authenticated;
revoke insert, update, delete, truncate on public.redemptions from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. The one door out of the wallet
-- ---------------------------------------------------------------------------
-- Every failure raises rather than returning a status, and each one carries its
-- own SQLSTATE so the app can say the true thing — "you need 300 more points"
-- reads very differently from "someone took the last one" and the client cannot
-- tell them apart from a message string it has to parse.
create or replace function public.spend_points(
  p_reward_id text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user     uuid := (select auth.uid());
  v_reward   public.rewards;
  v_balance  integer;
  v_existing public.redemptions;
  v_code     text;
  v_row      public.redemptions;
  v_has_email boolean;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key is required' using errcode = '22023';
  end if;

  -- A replay of a redemption that already went through returns the original
  -- rather than charging again. Checked before anything is locked, because the
  -- common case for this branch is a retry of a request whose response was lost.
  select * into v_existing
    from public.redemptions
   where user_id = v_user and idempotency_key = trim(p_idempotency_key);
  if found then
    return public.redemption_json(v_existing);
  end if;

  -- Thirty an hour, and the counter deliberately includes attempts that were
  -- refused: a client hammering the wallet with requests it knows will fail is
  -- exactly what this is here to stop. That is also why the number is not ten —
  -- a traveller who taps something they cannot afford a few times, changes
  -- their mind twice and comes back would spend a tighter budget on nothing.
  if not public.check_rate_limit(v_user, 'redeem', 30, interval '1 hour') then
    raise exception 'too many redemptions' using errcode = 'MS006';
  end if;

  select * into v_reward
    from public.rewards
   where id = p_reward_id and active;
  if not found then
    raise exception 'reward unavailable' using errcode = 'MS002';
  end if;

  -- A plush posted to a row that the anonymous-user sweep deletes next week is
  -- a plush nobody can be given. Digital and partner rewards stay open to
  -- guests: they cost nothing to hand out, and they are the reason a guest
  -- makes an account in the first place.
  if v_reward.kind = 'physical' then
    select (u.email is not null) into v_has_email
      from auth.users u where u.id = v_user;
    if not coalesce(v_has_email, false) then
      raise exception 'account required' using errcode = 'MS005';
    end if;
  end if;

  if not v_reward.repeatable
     and exists (select 1 from public.redemptions
                  where user_id = v_user and reward_id = v_reward.id) then
    raise exception 'already owned' using errcode = 'MS004';
  end if;

  -- The lock. Everything from here to the commit is one traveller's wallet and
  -- one row of stock, held against concurrent taps on a slow connection.
  select points_balance into v_balance
    from public.profiles
   where id = v_user
     for update;

  if coalesce(v_balance, 0) < v_reward.cost_points then
    raise exception 'insufficient points' using errcode = 'MS001';
  end if;

  if v_reward.stock is not null then
    update public.rewards
       set stock = stock - 1
     where id = v_reward.id and stock > 0;
    if not found then
      raise exception 'out of stock' using errcode = 'MS003';
    end if;
  end if;

  if v_reward.fulfillment = 'voucher' then
    -- Eight characters from an alphabet with no 0/O/1/I, because this gets read
    -- out loud across a counter. Collisions are caught by the unique index; at
    -- this catalogue's size a retry loop would be theatre.
    v_code := (
      select string_agg(
        substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
               1 + floor(random() * 32)::int, 1), '')
      from generate_series(1, 8)
    );
  end if;

  insert into public.redemptions
    (user_id, reward_id, cost_points, idempotency_key, code, status, expires_at)
  values
    (v_user, v_reward.id, v_reward.cost_points, trim(p_idempotency_key), v_code,
     case when v_reward.fulfillment = 'voucher' then 'issued' else 'fulfilled' end,
     case when v_reward.fulfillment = 'voucher' then now() + interval '14 days' end)
  returning * into v_row;

  -- Into the purchased bucket, not the daily one — see §7. A credit bought
  -- with points that expired at midnight would be the catalogue's first lie.
  update public.profiles
     set points_balance          = points_balance - v_reward.cost_points,
         model_credits_purchased = model_credits_purchased + v_reward.grant_model_credits,
         updated_at              = now()
   where id = v_user;

  return public.redemption_json(v_row);
end;
$$;

-- Shared by the success and the replay path so a retry cannot be told from the
-- original by the shape of what comes back.
create or replace function public.redemption_json(r public.redemptions)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id',             r.id,
    'reward_id',      r.reward_id,
    'cost_points',    r.cost_points,
    'code',           r.code,
    'status',         r.status,
    'expires_at',     r.expires_at,
    'created_at',     r.created_at,
    'points_balance', (select points_balance from public.profiles where id = r.user_id)
  );
$$;

revoke all on function public.redemption_json(public.redemptions) from public, anon, authenticated;
revoke all on function public.spend_points(text, text) from public, anon;
grant execute on function public.spend_points(text, text) to authenticated;

comment on function public.spend_points(text, text) is
  'The only way to spend points. Atomic against the profile row, idempotent on (user, idempotency_key), and never to be called from a client-side offline queue.';

-- ---------------------------------------------------------------------------
-- 7. Purchased 3D credits have to survive the night
-- ---------------------------------------------------------------------------
-- `profiles.model_credits` is a daily allowance, and the `reset-credits` cron
-- (migration 20260801120002) *assigns* it — 10 for a signed-up user, 3 for a
-- guest — rather than topping it up. A credit bought with points would sit in
-- that column until midnight and then be overwritten, which would make the
-- first reward in the catalogue a swindle.
--
-- So purchased credits live in their own column that nothing resets, and the
-- daily allowance is spent first. Both `consume_model_credit` and
-- `refund_model_credit` keep their signatures, so `backend/server-node`'s two
-- call sites need no change. The column itself is declared in §1.

create or replace function public.consume_model_credit(p_user uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_ok boolean;
begin
  -- Daily first: it expires tonight either way, and a purchased credit that
  -- was spent while a free one went unused is the version people write in to
  -- complain about.
  update public.profiles
     set model_credits = model_credits - 1,
         credits_reset_at = case
           when credits_reset_at < date_trunc('day', now())
           then now() else credits_reset_at end
   where id = p_user and model_credits > 0
  returning true into v_ok;

  if coalesce(v_ok, false) then
    return true;
  end if;

  update public.profiles
     set model_credits_purchased = model_credits_purchased - 1
   where id = p_user and model_credits_purchased > 0
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
  -- Always refunded to the purchased bucket, whichever one it came out of.
  -- The alternative loses a bought credit whenever an infrastructure failure
  -- happens to fall late in the day, and being slightly generous is the
  -- cheaper mistake.
  update public.profiles
     set model_credits_purchased = model_credits_purchased + 1
   where id = p_user;
end;
$$;

revoke all on function public.consume_model_credit(uuid) from public, anon, authenticated;
revoke all on function public.refund_model_credit(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. The opening catalogue
-- ---------------------------------------------------------------------------
-- Digital only. Nothing here needs a partner signed, a code scanned or an
-- object posted, which is what makes it shippable on its own — and the point of
-- shipping it on its own is to find out whether a visible ladder changes how
-- many tasks people finish, before anyone spends money on stock.
--
-- **Three rows, not the dozen the catalogue could hold.** Every one of these
-- does something the moment it is bought. The cosmetics that were drafted
-- alongside them — fennec variants, a folder cover — are not seeded, because
-- nothing renders them yet and a reward that changes nothing is the same
-- mistake as the Settings rows with an empty `onTap` that this app deliberately
-- removed rather than shipped. They go in with the assets, not before.
--
-- Prices are calibrated against a completed route: eleven stops at 30 points is
-- 330, so one route buys a reroll and a generation credit with change.
insert into public.rewards
  (id, title, blurb, kind, cost_points, fulfillment, grant_model_credits,
   grant_quest_rerolls, repeatable, sort_order)
values
  ('model_credit', '3D scan credit',
   'One more object turned into a model you can keep, on top of your daily allowance. It does not expire.',
   'digital', 150, 'instant', 1, 0, true, 10),

  ('model_credit_5', '3D scan credits ×5',
   'Five generations, for a day out with a lot worth scanning.',
   'digital', 650, 'instant', 5, 0, true, 20),

  ('quest_reroll', 'Extra quest reroll',
   'One more swap at a stop, past the two that the three quest types allow.',
   'digital', 100, 'instant', 0, 1, true, 30)
on conflict (id) do nothing;
