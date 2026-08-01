# 11 — Security Checklist

Consolidated review across every document. Ordered by what actually gets
exploited, not by what's most interesting.

---

## Open issues in the code today

These exist right now, in committed or staged code.

| # | Issue | Where | Severity |
| --- | --- | --- | --- |
| 1 | GPU endpoint is completely unauthenticated | `backend/hunyuan2.1/api.py:29` | **Critical** — direct financial loss |
| 2 | Endpoint URL committed to the repo | `backend/hunyuan2.1/api_test.py:3` | High (compounds #1) |
| 3 | `venv/` untracked but not ignored — 13,600 files | `.gitignore` | Medium — will be committed by accident |
| 4 | No request size or content validation before GPU work | `api.py:30-33` | High |
| 5 | `timeout=3600` on a GPU function | `api.py:21` | Medium — one hung call costs an hour of L4 |
| 6 | Absolute file paths persisted for captures | `ar_hunt_screen.dart:596` | Medium — data loss on iOS reinstall |
| 7 | Nominatim `User-Agent` has no contact info | `location_search_bar.dart:75` | Low — violates the usage policy; risks a block |
| 8 | No auth, no RLS, no user scoping anywhere | Whole app | Blocks everything else |

Fix #1 and #3 before the next push. #1 because it's spending real money on
someone else's terms, #3 because once 13,600 files are in git history they're
effectively permanent.

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
directly hits `ingest-pois`) across thousands of far-flung, never-revisited
coordinates. Each cold tile triggers a real Overpass query, a Wikidata SPARQL
call, and Wikipedia/Commons lookups — none of them free of rate limits, and
some of them shared public infrastructure that gets your app's `User-Agent`
blocked for every user if you exceed fair use. This is a newer, quieter cousin
of #1: instead of burning GPU seconds directly, it burns third-party API
goodwill and Supabase database writes. No credential needed, just varied
coordinates.
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

- [ ] RLS is **enabled** on every table in `public` — verify, don't assume
- [ ] Every policy has both `using` and `with check`
- [ ] Every policy names a role (`to authenticated`)
- [ ] `auth.uid()` is wrapped as `(select auth.uid())` for performance
- [ ] `model_credits` and `total_points` are not client-writable
- [ ] Storage policies match on `(storage.foldername(name))[1] = auth.uid()`
- [ ] The `models` bucket has no client insert policy
- [ ] Realtime publication is RLS-authorized
- [ ] `security definer` functions all set `search_path = ''` and fully qualify names
- [ ] **Tested with two real accounts**, not by reading the policies

That last one is the only test that counts. Sign in as A, capture the JWT, and
try to read B's rows directly against the REST API with `curl`.

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

- [ ] The app has no direct path to Overpass, Geoapify, Wikidata, or any other maps provider — every call goes through `ingest-pois` ([12](12-poi-sources-and-ingestion.md))
- [ ] Ingestion is keyed by tile, not by raw `(lat, lng)` — repeated nearby requests hit the cache, not the provider
- [ ] Per-user rate limit on distinct-tile requests per hour (reuses `check_rate_limit` from [07](07-securing-the-3d-endpoint.md))
- [ ] `radius_km` is capped server-side before it's used to compute covering tiles
- [ ] A cold-tile request degrades to curated fallback locations if the provider is unreachable, rather than blocking or erroring
- [ ] Provider `User-Agent` headers carry real contact information
- [ ] Ingestion failures are logged with tile id, not with the requesting user's coordinates history (privacy — see below)

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

1. Add proxy auth to the Modal endpoints ([07](07-securing-the-3d-endpoint.md), layer 3). One decorator argument.
2. Set a Modal spend limit. One dashboard setting.
3. Update `.gitignore` before the venv gets committed.

Those three take under an hour and remove the only issue in this document that
is actively costing money.
