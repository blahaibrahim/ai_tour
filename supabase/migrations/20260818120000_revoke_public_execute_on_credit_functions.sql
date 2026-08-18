-- Close the PUBLIC grant on the two model-credit functions.
--
-- `create function` grants EXECUTE to PUBLIC by default, and `anon` inherits
-- PUBLIC. Migration 20260801120002 and 20260817120000 both ended with
--
--     revoke execute on function ... from anon, authenticated;
--
-- which revokes the *role* grants and leaves the PUBLIC one untouched — so both
-- functions stayed callable over PostgREST by anyone holding the publishable
-- key, which ships inside the APK (see the `.env` warning in docs/SYSTEM.md
-- §10). `refund_model_credit(p_user uuid)` takes an arbitrary user id and
-- increments their credit balance, so that was a way for anybody to mint
-- unlimited GPU generations onto any account; `consume_model_credit` was a way
-- to drain someone else's.
--
-- Found by `get_advisors` immediately after applying 20260817120000, not by
-- reading the grant tables: `information_schema.routine_privileges` reports the
-- PUBLIC grantee as `PUBLIC`, so a query filtering on lowercase `public` shows
-- a clean result for a function anyone can call. `has_function_privilege
-- ('anon', oid, 'EXECUTE')` is the check that does not lie.
--
-- Neither function is called by a client. Both are called by
-- `backend/server-node/src/routes/models.ts` with the service_role key, which
-- holds its own grant and is unaffected.
--
-- The lesson generalises: revoking from `anon, authenticated` is not enough for
-- a SECURITY DEFINER function. It has to include `public` — which is what
-- `award_task_points`, `spend_points` and `redemption_json` already do.
revoke all on function public.consume_model_credit(uuid) from public, anon, authenticated;
revoke all on function public.refund_model_credit(uuid) from public, anon, authenticated;

comment on function public.consume_model_credit(uuid) is
  'Server-only. EXECUTE revoked from public/anon/authenticated — call it as service_role. Spends the daily allowance before anything bought with points.';

comment on function public.refund_model_credit(uuid) is
  'Server-only. EXECUTE revoked from public/anon/authenticated — call it as service_role. Refunds into the purchased bucket so a refund never evaporates at midnight.';
