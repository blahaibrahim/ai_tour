-- Lock down rate_limit_events.
--
-- The table had RLS disabled *and* full DML granted to anon and authenticated,
-- so anyone holding the publishable key could run
--
--     delete from public.rate_limit_events where user_id = '<their uid>';
--
-- and reset every limit that gates them — including the 20/day generate_3d
-- ceiling, which is the thing standing between a signed-in anonymous user and
-- unbounded L4 GPU spend. The limiter was advisory against anyone who bothered
-- to look.
--
-- Nothing legitimate is lost by closing it: `check_rate_limit` is the only
-- code anywhere that reads or writes this table (verified against pg_proc),
-- and it is SECURITY DEFINER, so it runs as the owner and is unaffected by
-- both the revoke and the RLS. service_role keeps its grants and bypasses RLS,
-- so the backend, migrations, the dashboard and local debugging scripts all
-- continue to work exactly as before.
--
-- Deliberately no policies: "no policy" means "no rows for anyone but the
-- owner and service_role", which is precisely the intent. A policy here would
-- only re-open a door nothing needs.

revoke all on public.rate_limit_events from anon, authenticated;

alter table public.rate_limit_events enable row level security;

comment on table public.rate_limit_events is
  'Rate-limit ledger. Accessed only via public.check_rate_limit (SECURITY '
  'DEFINER). RLS is on with no policies and anon/authenticated hold no grants '
  'by design — see migration 20260805203000. Do not add a policy to "make it '
  'readable"; read it as service_role.';
