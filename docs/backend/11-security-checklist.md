# 11 — Security Checklist

> **Status: Partially addressed — new work only.** RLS now genuinely exists
> for the Supabase catalogue and ingestion tables, and was verified with live
> calls using the real anon key (not just reviewed) — see doc 02's status
> note and the "Threat model" section below for the one gap this surfaced
> mid-build. Nothing about the 3D endpoint (issues #1, #2, #4, #5 below) has
> changed. One new gap this session introduced: `POST /api/poi/ingest`
> (doc 12) has no rate limiting of its own — see the updated table below.

Consolidated review across every document. Ordered by what actually gets
exploited, not by what's most interesting.

---

## Open issues in the code today

These exist right now, in committed or staged code.

| # | Issue | Where | Severity |
| --- | --- | --- | --- |
| 1 | GPU endpoint is completely unauthenticated | `backend/hunyuan2.1/api.py:29` | **Critical** — direct financial loss, still unfixed |
| 2 | Endpoint URL committed to the repo | `backend/hunyuan2.1/api_test.py:3` | High (compounds #1), still unfixed |
| 3 | ~~`venv/` untracked but not ignored~~ | `.gitignore` | **Fixed** — `backend/**/venv/`, `__pycache__/`, and `.env` are gitignored; confirmed nothing under `backend/server/venv` is tracked |
| 4 | No request size or content validation before GPU work | `api.py:30-33` | High, still unfixed |
| 5 | `timeout=3600` on a GPU function | `api.py:21` | Medium — one hung call costs an hour of L4, still unfixed |
| 6 | Absolute file paths persisted for captures | `ar_hunt_screen.dart:596` | Medium — data loss on iOS reinstall, still unfixed (no Flutter work this session) |
| 7 | Nominatim `User-Agent` has no contact info | `location_search_bar.dart:75` | Low — still unfixed. Note: the *new* ingestion clients (Overpass/Wikidata/Wikipedia/Commons) do send a real contact-carrying User-Agent via `OVERPASS_CONTACT` — this specific pre-existing Nominatim call in the Flutter app was not touched |
| 8 | ~~No auth, no RLS, no user scoping anywhere~~ | Whole app | **Partially addressed** — RLS now exists and is verified for the Supabase catalogue/ingestion tables (doc 02, 12). Still true for everything else: no user accounts exist anywhere, so there's nothing yet for per-user RLS to scope |
| 9 | ~~`POST /api/poi/ingest` has no rate limit~~ | `backend/server/routes/poi.py` | **Fixed** — `check_rate_limit` RPC is called (10 requests per user per day) before any ingestion work begins, same pattern as the 3D endpoint. Verified in `poi.py`. |

Fix #1 before the next push — it's spending real money on someone else's
terms and remains the single most urgent item in this entire plan.

```gitignore
backend/**/venv/
backend/**/__pycache__/
backend/**/*.pyc
backend/**/results/
backend/**/*.glb
.env
**/.env.local
supabase/.env
```

---

## Threat model

Who actually attacks an app like this, in order of likelihood:

**1. Opportunistic GPU abuse.** Someone finds the Modal URL — scraped from
GitHub, pulled from an APK, or guessed from the predictable
`{workspace}--{app}-{fn}.modal.run` pattern — and loops requests. No skill
required. Highest probability, highest immediate cost.
→ [07](07-securing-the-3d-endpoint.md)

**2. Quota farming.** A legitimate user discovers reinstalling resets their free
generations. Costs money at a slower rate; erodes any paid tier.
→ [01](01-auth-and-accounts.md), [07](07-securing-the-3d-endpoint.md)

**3. POI ingestion abuse.** Someone scripts requests for `nearby_locations` (or
directly hits `/api/poi/ingest`) across thousands of far-flung, never-revisited
coordinates. Each cold tile triggers a real Overpass query, a Wikidata SPARQL
call, and Wikipedia/Commons lookups — none of them free of rate limits, and
some of them shared public infrastructure that gets your app's `User-Agent`
blocked for every user if you exceed fair use. This is a newer, quieter cousin
of #1: instead of burning GPU seconds directly, it burns third-party API
goodwill and Supabase database writes. No credential needed, just varied
coordinates.
**Now real, not hypothetical**: `/api/poi/ingest` (docs/backend/12) implements
exactly this call shape. Partially mitigated by design — `MAX_TILES_PER_INGEST
= 3` and the `poi_tiles` cache bound the cost of any *single* call, and this
was tuned down from 9 after empirically hitting Overpass's rate limit during
testing (real evidence the limit is close, not theoretical). **Not mitigated**:
nothing stops repeated calls from the same caller — see open issue #9 above.
→ [12](12-poi-sources-and-ingestion.md)

**4. Cross-user data access.** A missing or wrong RLS policy lets one user read
another's captures and trips. Low probability if RLS is done properly, high
impact — this is the one that ends up in the press.
→ [02](02-cloud-database-schema.md), [05](05-storage-and-media.md)

**5. Malicious upload.** Decompression bomb, malformed image targeting native
decoders, or illegal content stored in your bucket.
→ [07](07-securing-the-3d-endpoint.md)

**6. Prompt injection.** Steering the LLM through crafted input. Low impact
here because model output only selects from server-supplied ids, which are
themselves drawn only from scored, provider-sourced candidates — see
[12](12-poi-sources-and-ingestion.md).
→ [08](08-llm-and-ai-features.md)

**7. Device compromise.** A stolen phone or a rooted device with a readable
session token.
→ [01](01-auth-and-accounts.md), [03](03-local-database-schema.md)

Notably absent: SQL injection (parameterized RPCs), XSS (no web surface), CSRF
(no cookie auth). Don't spend effort there.

---

## Pre-launch gate

Nothing ships until every box is ticked.

### Secrets

- [ ] `service_role` key appears nowhere in `lib/`, `android/`, `ios/`, or git history
- [ ] Modal proxy credentials exist only in Supabase secrets
- [ ] LLM provider keys exist only in Edge Function env
- [ ] `gitleaks detect --no-git` and a full-history scan both come back clean
- [ ] Any key ever committed has been **rotated**, not just deleted
- [ ] `strings` over the release APK reveals no Modal URL and no non-anon key
- [ ] `.env` and `supabase/.env` are gitignored

### Authentication

- [ ] Anonymous sign-in is rate-limited or CAPTCHA-gated
- [ ] Sessions stored in `flutter_secure_storage`, not `SharedPreferences`
- [ ] Expired JWT triggers silent refresh; rejected refresh triggers clean sign-out
- [ ] Sign-out clears local user data and cached media
- [ ] Account deletion removes rows, storage objects, and the auth user

### Authorization (RLS)

No user-scoped tables exist yet (no `profiles`, `trips`, `artifacts`, …), so
most of this section is still forward-looking. What *does* exist — the
catalogue and ingestion tables from docs 02/12 — has been checked:

- [x] RLS is **enabled** on every table in `public` that exists so far (all 8: `regions`, `region_translations`, `locations`, `location_translations`, `location_tasks`, `location_task_translations`, `poi_tiles`, `poi_source_links`) — confirmed via `get_advisors`, not assumed
- [ ] Every policy has both `using` and `with check` — n/a as written: today's policies are all `select`-only (catalogue is world-readable, nothing is client-writable), so there's no `with check` to have yet
- [x] Every policy names a role (`to anon, authenticated`) — all six catalogue select policies do
- [ ] `auth.uid()` is wrapped as `(select auth.uid())` for performance — n/a, no policy references `auth.uid()` yet
- [ ] `model_credits` and `total_points` are not client-writable — n/a, table doesn't exist
- [ ] Storage policies match on `(storage.foldername(name))[1] = auth.uid()` — n/a, no storage yet
- [ ] The `models` bucket has no client insert policy — n/a, no storage yet
- [ ] Realtime publication is RLS-authorized — n/a, nothing uses Realtime yet
- [x] Functions that need elevated access use `security invoker`, not `security definer` — all six ingestion/catalogue functions (`nearby_locations`, `find_location_match`, `upsert_ingested_location`, `upsert_poi_tile`, `touch_updated_at`) do; the privilege boundary is enforced by *which role calls them* (service_role vs. anon) rather than by escalating inside the function, which is the safer pattern this checklist's `security definer` warnings point toward
- [x] **Tested against the real access boundary that exists today**, not by reading the policies — no user accounts to test A-vs-B with yet, but the equivalent test for this stage — anon key vs. service_role-only RPCs — was run for real and **caught a genuine gap**: `revoke execute ... from public` alone left `anon`/`authenticated` with access anyway, because Supabase grants those roles direct `EXECUTE` via `ALTER DEFAULT PRIVILEGES`, independent of the `PUBLIC` grant. Fixed by revoking from `anon, authenticated` explicitly (migration `poi_ingestion_functions_lockdown`) and re-verified with a live anon-key call returning `permission denied`. Worth generalizing: **when this project's real user-scoped tables land, don't trust `revoke ... from public` alone — verify with the actual anon key.**

### The 3D endpoint

- [ ] Modal endpoints require proxy auth (or a constant-time-compared secret)
- [ ] The app has no path to Modal that doesn't go through Supabase
- [ ] Edge Function verifies the JWT via `auth.getUser()`, not by decoding it
- [ ] Storage paths from the client are prefix-checked against the caller's uid
- [ ] Quota consumption is a single conditional `UPDATE`, not read-then-write
- [ ] Rate limit enforced per user and per window
- [ ] Image validated for size, format, and pixel count before the GPU
- [ ] `Image.MAX_IMAGE_PIXELS` set
- [ ] No request data reaches a shell command
- [ ] `timeout` ≤ 900 s, `max_containers` bounded
- [ ] Modal spend limit configured
- [ ] NSFW screening runs before generation
- [ ] Failed jobs refund credits; user-error failures do not

### POI ingestion

- [x] The app has no direct path to Overpass, Geoapify, Wikidata, or any other maps provider — every call goes through `POST /api/poi/ingest` ([12](12-poi-sources-and-ingestion.md)) — true today by construction (Flutter doesn't call anything yet), and the ingestion clients live only in `backend/server/ingestion/`
- [x] Ingestion is keyed by tile, not by raw `(lat, lng)` — repeated nearby requests hit the cache, not the provider — verified live: a second `POST /api/poi/ingest` call over overlapping ground correctly skipped every already-`ok` tile and only retried the ones marked `failed`
- [ ] Per-user rate limit on distinct-tile requests per hour — **not implemented**, this is open issue #9 above
- [x] `radius_km` is capped server-side before it's used to compute covering tiles — `MAX_RADIUS_KM = 50` in `routes/poi.py`, tighter than itinerary's 500km cap since this one triggers real ingestion work
- [x] A cold-tile request degrades to curated fallback locations if the provider is unreachable, rather than blocking or erroring — verified: `overpass.fetch_pois` returns `[]` on failure rather than raising, and the tile gets marked `failed` with a short retry TTL instead of poisoning the cache
- [ ] Provider `User-Agent` headers carry real contact information — the mechanism exists (`OVERPASS_CONTACT` env var, read by every ingestion client), but **the variable itself is currently unset** — falls back to a `no-contact-configured` placeholder. This is a manual step: add a real contact email or project URL to `backend/.env` before running ingestion against real traffic, not just test volumes
- [x] Ingestion failures are logged with tile id, not with the requesting user's coordinates history — `ingest.py`'s exception handler logs `tile_id`, never the original request's raw lat/lng

### Input validation

- [ ] Bucket-level size limits and MIME allowlists set
- [ ] `p_limit` and `p_min_score` bounds enforced inside `nearby_locations`
- [ ] Enum values validated server-side before insert
- [ ] Free-text length capped before it enters a prompt
- [ ] LLM-returned ids validated against the candidate set
- [ ] LLM candidate set itself is validated as score-floor-compliant before the prompt is built (defense if the RPC is ever called incorrectly)

### Client

- [ ] Release builds use `--obfuscate --split-debug-info` (raises the bar; not a control)
- [ ] Certificate pinning considered for the Supabase host — optional, and note it complicates key rotation
- [ ] No secrets in `--dart-define` (recoverable from the binary)
- [ ] Debug logging of tokens and PII stripped from release builds
- [ ] `flutter_secure_storage` configured with `encryptedSharedPreferences: true` on Android

### Privacy

- [ ] EXIF stripped from every uploaded image
- [ ] Location permission requested with a clear rationale at point of use
- [ ] Privacy policy exists and the settings link resolves (`settings_screen.dart:63` currently goes nowhere)
- [ ] Data export available on request
- [ ] Anonymous account retention documented
- [ ] Third-party data flows disclosed: Supabase, Modal, the chosen LLM provider, OSM/Nominatim, CartoDB, Wikidata/Wikipedia/Commons, and any commercial maps API in use

### Third-party compliance

- [ ] OpenStreetMap attribution displayed on the map and for POI data sourced from it ([12](12-poi-sources-and-ingestion.md))
- [ ] CartoDB attribution displayed (`map_screen.dart:73`)
- [ ] Nominatim `User-Agent` includes a contact address, and requests are ≤ 1/sec
- [ ] Overpass/Geoapify `User-Agent` includes a contact address; ingestion respects the provider's fair-use rate limits
- [ ] Every displayed Commons photo carries its required attribution and licence — stored per-row in `locations.photo_attribution` / `photo_license` ([12](12-poi-sources-and-ingestion.md)), not assumed
- [ ] Wikipedia-derived text usage complies with CC BY-SA (verbatim extracts attributed; LLM-rewritten summaries still credit the source article)
- [ ] If Google Places (or any provider with caching restrictions) is used for enrichment, verify content is fetched live rather than persisted — see the Google Places note in [12](12-poi-sources-and-ingestion.md)
- [ ] Hunyuan3D 2.1 licence terms reviewed against commercial use — see [06](06-3d-generation-pipeline.md)
- [ ] LLM provider terms permit your use case

The Nominatim one is easy to dismiss and it will bite you: the current
`'ai_tour_app'` User-Agent (`location_search_bar.dart:75`) has no contact
information, which the usage policy asks for. Blocks are applied by
User-Agent. Add a contact URL, and consider self-hosting or switching to a
provider with a real free tier if search volume grows.

---

## Monitoring

You cannot respond to what you can't see.

| Signal | Threshold | Why |
| --- | --- | --- |
| `model_jobs` created per hour | > 3× baseline | Abuse or a client retry loop |
| Modal spend | Daily budget alert | The last line of defence |
| Auth failures per IP | > 20/min | Credential stuffing |
| Anonymous sign-ups per hour | > 5× baseline | Quota farming |
| Job failure rate | > 20% | Broken pipeline, refunds owed |
| Edge Function 5xx rate | > 1% | Provider outage or a bug |
| Storage growth per day | > 100 MB | Retention policy not working |
| Distinct POI tiles requested per user per hour | > 20× baseline | Ingestion-endpoint abuse ([12](12-poi-sources-and-ingestion.md)) |
| Overpass/Geoapify error or throttle rate | > 5% | Approaching a fair-use limit — switch provider or self-host before it becomes a block |
| POI cache hit rate (`FetchedAreas` / total requests) | Trending down | Tile TTL too short, or genuinely new geography — check which before tuning |

Add Sentry (free tier) for client crashes and Edge Function errors. Do not log
JWTs, storage paths with user ids, prompts, or image bytes.

---

## Incident playbook

**Suspected key leak.** Rotate immediately — Supabase service role from the
dashboard, Modal proxy tokens from the workspace, LLM keys at the provider.
Redeploy Edge Functions. Review logs for use of the old key. Rotation first,
investigation second.

**GPU abuse in progress.** Set `max_containers=0` to stop all work, or delete
the Modal app. Then find whether it came through the Edge Function (a quota
bug) or directly (a proxy-auth bug), fix that, and redeploy.

**Cross-user data exposure.** Disable the affected table's client access
(`revoke` from `authenticated`), fix the policy, verify with two accounts, then
restore. Assess what was accessible and for how long; disclose if required.

---

## What to do first

If you do nothing else this week:

1. Add proxy auth to the Modal endpoints ([07](07-securing-the-3d-endpoint.md), layer 3). One decorator argument. **Still the top priority — unchanged by everything built this session.**
2. Set a Modal spend limit. One dashboard setting.
3. ~~Update `.gitignore` before the venv gets committed.~~ **Done** — `backend/**/venv/` and friends are ignored, confirmed nothing under it is tracked.

Items 1–2 take under an hour and remove the only issue in this document that
is actively costing money. Two smaller items surfaced by this session's work,
worth doing at the same time since they're each a few minutes: set a real
`OVERPASS_CONTACT` in `backend/.env` before running ingestion at any volume
(see the POI ingestion checklist above), and add a per-caller rate limit to
`POST /api/poi/ingest` before it's reachable from anywhere but a developer's
own testing (open issue #9).
