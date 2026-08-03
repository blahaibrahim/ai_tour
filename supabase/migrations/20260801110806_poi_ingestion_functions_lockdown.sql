-- Supabase grants EXECUTE on new public-schema functions to anon and
-- authenticated directly via ALTER DEFAULT PRIVILEGES, separately from the
-- PUBLIC pseudo-role grant already revoked in poi_ingestion_functions. That
-- means the earlier "revoke ... from public" left anon/authenticated with
-- access anyway — caught by testing with the actual anon key, not assumed.
revoke execute on function public.find_location_match(double precision, double precision, text, double precision, real) from anon, authenticated;
revoke execute on function public.upsert_ingested_location(
  text, double precision, double precision, text, text, text, numeric, jsonb,
  text, text, integer, text, text, text, text, text, boolean
) from anon, authenticated;
revoke execute on function public.upsert_poi_tile(text, double precision, double precision, double precision, double precision, text, integer, text, integer) from anon, authenticated;
