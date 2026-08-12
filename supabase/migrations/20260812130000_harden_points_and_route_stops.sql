-- Two holes, closed.
--
-- 1. `public.route_stops` sat in an exposed schema with RLS switched off, so
--    anyone holding the publishable key could read or rewrite every row.
--
-- 2. Points were client-declared. `authenticated` held UPDATE on every column
--    of `public.profiles` — including `total_points` — and INSERT on
--    `public.task_completions` with a caller-supplied `points`. The ledger
--    stopped a completion being *replayed*, but nothing stopped a client
--    simply asserting a score.
--
-- Neither change alters what the app can do. The client never wrote either
-- table: it reads `profiles.total_points`, and it now earns points through an
-- RPC instead of an insert.

-- ---------------------------------------------------------------------------
-- 1. route_stops
-- ---------------------------------------------------------------------------
-- RLS on with no policies, and no grants — the same deliberate lockdown as
-- `rate_limit_events` (see migration 20260805203000). This is not an oversight
-- to be "fixed" later by adding a policy.
--
-- A route's stop list is server-owned: written once at generation, never
-- updated, and read back by joining onto `pois`. Only the trusted server has
-- any business touching it, and service_role bypasses RLS, so it needs no
-- policy to keep working.
--
-- NOTE for whoever implements `RouteRepository.persist` (currently a stub in
-- backend/server-node/src/routeGeneration/data/routeRepository.ts): it must use
-- the admin client from `ingestion/supabaseAdmin`, not the anon-key client in
-- `data/supabaseClient.ts`. The anon client has no grants here and will fail.
alter table public.route_stops enable row level security;
revoke all on public.route_stops from anon, authenticated;

comment on table public.route_stops is
  'Server-owned route contents. RLS is on with no policies and anon/authenticated hold no grants by design — write it as service_role. Do not add a policy to "make it readable".';

-- ---------------------------------------------------------------------------
-- 2. Points integrity
-- ---------------------------------------------------------------------------

-- The score column becomes read-only to clients. The four presentational
-- columns stay writable so a profile-editing screen needs no migration; the
-- two that represent earned or purchased value (`total_points`,
-- `model_credits`) are now reachable only through the functions that own them
-- — this one and `consume_model_credit`.
revoke insert, update, delete, truncate on public.profiles from anon, authenticated;
grant update (display_name, locale, theme_mode, units_metric)
  on public.profiles to authenticated;

-- The ledger becomes append-only *through one door*. Clients keep SELECT, so a
-- traveller can still read their own history under the existing policy.
revoke insert, update, delete, truncate on public.task_completions from anon, authenticated;
revoke all on public.task_completions from anon;

-- Unreachable now that the grant is gone, and misleading to leave behind: it
-- would imply a direct insert path that no longer exists.
drop policy if exists "own task completions insert" on public.task_completions;

-- The one door.
--
-- SECURITY DEFINER is load-bearing rather than convenient: the whole point is
-- to do something the caller cannot do for themselves. It follows the rules
-- that makes safe — an explicit `auth.uid()` check as the first statement, a
-- pinned empty `search_path`, fully-qualified references, and EXECUTE revoked
-- from everyone except signed-in users.
--
-- It has to live in `public` because PostgREST only exposes RPCs from the
-- API schema, so the revoke below is what stands in for hiding it.
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

  -- The award is decided here, not by the caller. Every task is worth the same
  -- today; when that stops being true this is the single place it changes, and
  -- it stays out of the client's reach either way.
  v_points := 30;

  -- Idempotent by the same key the ledger has always used, so a retried
  -- outbox entry or a replayed session is absorbed silently instead of
  -- awarding twice. `do nothing` also means the trigger does not fire, so the
  -- counter is untouched on a duplicate.
  insert into public.task_completions
    (user_id, completion_key, route_id, poi_id, task_type, points)
  values
    (v_user, p_completion_key, p_route_id, p_poi_id,
     coalesce(nullif(trim(p_task_type), ''), 'unknown'), v_points)
  on conflict (user_id, completion_key) do nothing;

  -- Returned whether or not anything was inserted, so the caller always ends
  -- up holding the authoritative total and never has to infer it by adding.
  select total_points into v_total from public.profiles where id = v_user;
  return coalesce(v_total, 0);
end;
$$;

revoke all on function public.award_task_points(text, text, text, text) from public, anon;
grant execute on function public.award_task_points(text, text, text, text) to authenticated;

comment on function public.award_task_points(text, text, text, text) is
  'The only way to earn points. Decides the award server-side and is idempotent on (user, completion_key). Returns the caller''s new lifetime total.';
