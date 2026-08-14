-- What a POI is worth visiting, on the same 0–100-ish scale `locations`
-- already uses.
--
-- The ingestion pipeline has computed this all along (`scoring.computeScore`,
-- from Wikidata presence, heritage status, Wikipedia pageviews and tag
-- quality) and then discarded it on the way into `pois`. That left the route
-- module with no way to rank one candidate above another, which is why it
-- could only take *every* eligible POI and report afterwards how many days
-- that would need. A budget cannot be fitted without knowing what is worth
-- keeping.
--
-- Nullable rather than defaulted to zero: null means "never scored", which is
-- true of anything hand-authored, and is different from "scored and found
-- uninteresting". The selector treats null as mid-ranked rather than worthless.
alter table public.pois add column if not exists interest_score numeric;

-- The same breakdown `locations.score_breakdown` carries, for the same reason:
-- a score with no explanation cannot be argued with when a POI ranks wrongly.
alter table public.pois add column if not exists score_breakdown jsonb;

-- Ranking within a city is the query the selector runs.
create index if not exists idx_pois_city_score
  on public.pois (city_id, interest_score desc nulls last)
  where deleted_at is null and status = 'published';
