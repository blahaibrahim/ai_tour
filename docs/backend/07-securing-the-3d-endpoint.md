# 07 — Securing the 3D Endpoint

> **Status: Fully implemented.** Layers 1 through 4 are fully implemented. The Flask backend validates Supabase JWTs, enforces rate limits, consumes model credits (quota), and securely proxies requests to the Modal endpoint. The Modal worker itself verifies the file extension, ensures pixel bounds, runs NSFW image detection, and pushes directly to Supabase storage.

## Current exposure

```python
# backend/hunyuan2.1/api.py:29
@modal.fastapi_endpoint(method="POST")
async def generate_3d_api(file: UploadFile = File(...)):
```

No authentication. Anyone who has the URL can run an L4 GPU for up to an hour
per request, at your expense, as many times as they like.

```python
# backend/hunyuan2.1/api_test.py:3
api_url = "https://blahaibrahim--hunyuan3d-api-generate-3d-api.modal.run"
```

The URL is in the repository. Modal endpoint URLs follow a predictable
`{workspace}--{app}-{function}.modal.run` pattern, so they aren't secret even
when they aren't published — treat obscurity as worth nothing.

**Concrete attack**: a script posting a 1×1 JPEG in a loop. Each request
occupies the GPU. With `max_containers=1` that also denies service to real
users while the bill runs. There's no rate limit, no quota, and no way to tell
whose request it was.

Fixing this is the highest-priority item in this whole plan. Everything else
can ship late; this cannot ship at all in its current form.

## Defence in depth

Five layers. Each is cheap; together they close the problem.

```
┌─ 1 ─ App never holds a secret ──────────────────────────────┐
│      Calls Supabase Edge Function with its own user JWT     │
├─ 2 ─ Edge Function authenticates and authorises ────────────┤
│      Verify JWT · rate limit · quota · validate input       │
├─ 3 ─ Modal accepts calls only from the Edge Function ───────┤
│      Proxy auth token / shared secret in a Modal Secret     │
├─ 4 ─ The worker re-validates its input ─────────────────────┤
│      Size, MIME, decode, dimensions, pixel budget           │
└─ 5 ─ Hard resource ceilings ────────────────────────────────┘
       timeout · max_containers · budget alert
```

### Layer 1 — the app holds nothing

The Flutter app calls only Supabase, with the user's own JWT that
`supabase_flutter` manages. There is no Modal credential, no shared secret, and
no API key anywhere in `lib/` or in the built APK.

This is non-negotiable: an APK is a zip file. `unzip` plus `strings` recovers
any constant you compile in, `--dart-define` included. Obfuscation delays this
by minutes, not days.

```dart
final res = await supabase.functions.invoke('request-model', body: {
  'artifact_id': artifact.id,
  'image_path': 'captures/$userId/${artifact.id}.jpg',
  'image_sha256': sha,
});
```

The image is uploaded to Storage first, under a path RLS already restricts to
this user ([05](05-storage-and-media.md)). The function receives a *reference*,
not bytes — which also keeps the request small and retryable.

### Layer 2 — the Edge Function

This is where every policy decision lives.

```typescript
// supabase/functions/request-model/index.ts
import { createClient } from 'jsr:@supabase/supabase-js@2';

Deno.serve(async (req) => {
  // --- authenticate -------------------------------------------------
  const jwt = req.headers.get('Authorization')?.replace('Bearer ', '');
  if (!jwt) return json({ error: 'unauthorized' }, 401);

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: `Bearer ${jwt}` } } },
  );
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) return json({ error: 'unauthorized' }, 401);

  // --- validate -----------------------------------------------------
  const { artifact_id, image_path, image_sha256 } = await req.json();
  if (!image_path?.startsWith(`captures/${user.id}/`)) {
    return json({ error: 'forbidden_path' }, 403);   // no reading others' files
  }
  if (!/^[a-f0-9]{64}$/.test(image_sha256 ?? '')) {
    return json({ error: 'bad_request' }, 400);
  }

  // --- admin client, past this point --------------------------------
  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // --- quota (atomic) -----------------------------------------------
  const { data: ok } = await admin.rpc('consume_model_credit', { p_user: user.id });
  if (!ok) return json({ error: 'quota_exceeded' }, 429);

  // --- dedupe -------------------------------------------------------
  const { data: hit } = await admin.from('model_jobs')
    .select('output_path').eq('input_sha256', image_sha256)
    .eq('status', 'succeeded').limit(1).maybeSingle();
  if (hit) {
    await admin.rpc('refund_model_credit', { p_user: user.id });
    await admin.from('artifacts')
      .update({ model_path: hit.output_path }).eq('id', artifact_id);
    return json({ cached: true, output_path: hit.output_path });
  }

  // --- create the job ----------------------------------------------
  const { data: job } = await admin.from('model_jobs').insert({
    user_id: user.id, artifact_id,
    input_path: image_path, input_sha256: image_sha256,
    status: 'queued',
  }).select('id').single();

  // --- hand off to Modal -------------------------------------------
  const { data: signed } = await admin.storage.from('captures')
    .createSignedUrl(image_path.replace('captures/', ''), 600);

  const modalRes = await fetch(Deno.env.get('MODAL_SUBMIT_URL')!, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Modal-Key':    Deno.env.get('MODAL_PROXY_KEY')!,
      'Modal-Secret': Deno.env.get('MODAL_PROXY_SECRET')!,
    },
    body: JSON.stringify({ job_id: job.id, image_url: signed.signedUrl }),
  });

  if (!modalRes.ok) {
    await admin.from('model_jobs').update({
      status: 'failed', error_code: 'submit_failed',
    }).eq('id', job.id);
    await admin.rpc('refund_model_credit', { p_user: user.id });
    return json({ error: 'upstream_unavailable' }, 503);
  }

  const { call_id } = await modalRes.json();
  await admin.from('model_jobs')
    .update({ modal_call_id: call_id, status: 'processing' }).eq('id', job.id);

  return json({ job_id: job.id });
});
```

Points worth dwelling on:

**Verify the JWT properly.** `auth.getUser()` with the user's token validates
signature and expiry server-side. Do not decode the JWT yourself and trust the
`sub` claim — an unverified JWT is a user-supplied string.

**Check the path prefix.** Without `image_path.startsWith('captures/{uid}/')`,
a user submits someone else's storage path and the service-role client happily
signs it. The service role bypasses RLS, so *you* are the only check at that
point. Every service-role code path needs this discipline.

**Deploy with JWT verification on** (the default). If you ever pass
`--no-verify-jwt`, the function is public.

### Quota must be atomic

```sql
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
```

The `where model_credits > 0` inside the `UPDATE` is what makes it safe. A
read-then-write pair (`select credits; if credits > 0 then update`) lets ten
concurrent requests all read `1` and all proceed. Row-level locking during the
conditional update makes that impossible.

Revoking execute from client roles means only the service role can call it.

Daily top-up:

```sql
select cron.schedule('reset-credits', '0 0 * * *', $$
  update public.profiles
     set model_credits = case when id in (
           select id from auth.users where email is not null
         ) then 10 else 3 end,
         credits_reset_at = now();
$$);
```

Claimed accounts get more than anonymous ones — this caps reinstall farming
and doubles as a reason to sign up ([01](01-auth-and-accounts.md)).

### Rate limiting

Quota caps the day; rate limiting caps the burst.

```sql
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
```

Suggested limits: 3 model requests per 10 minutes, 20 per day. Also rate-limit
anonymous sign-up per IP at the Supabase Auth level, or the quota is bypassed
by making new users.

### Layer 3 — lock Modal to the Edge Function

Modal supports proxy auth on web endpoints:

```python
@modal.fastapi_endpoint(method="POST", requires_proxy_auth=True)
```

Modal then requires `Modal-Key` and `Modal-Secret` headers on every request and
rejects anything else at the platform edge — before your container starts, so
an unauthenticated flood costs nothing.

Create the token in the Modal dashboard, store both halves in Supabase secrets:

```bash
supabase secrets set MODAL_PROXY_KEY=wk-xxxx MODAL_PROXY_SECRET=ws-xxxx
supabase secrets set MODAL_SUBMIT_URL=https://<workspace>--hunyuan3d-api-submit.modal.run
```

If you'd rather not use proxy auth, the fallback is a shared bearer secret
compared in constant time:

```python
import hmac, os
from fastapi import Header, HTTPException

def require_secret(authorization: str = Header(None)):
    expected = os.environ["INTERNAL_API_SECRET"]        # from modal.Secret
    supplied = (authorization or "").removeprefix("Bearer ").strip()
    if not hmac.compare_digest(supplied, expected):
        raise HTTPException(status_code=401)
```

`hmac.compare_digest`, not `==`. String equality short-circuits on the first
differing byte and leaks the secret to a timing attack. Proxy auth is better
because it rejects before any compute is spent; use the shared secret only if
proxy auth doesn't fit.

Rotate the token on a schedule and immediately if anyone leaves the project.

### Layer 4 — validate in the worker

The Edge Function is trusted, but a bug there shouldn't reach the GPU. Validate
again where the compute is spent.

```python
from PIL import Image
import io

MAX_BYTES = 10 * 1024 * 1024
MAX_PIXELS = 24_000_000
ALLOWED = {"JPEG", "PNG", "WEBP"}

Image.MAX_IMAGE_PIXELS = MAX_PIXELS      # blocks decompression bombs

def validate(data: bytes) -> Image.Image:
    if len(data) > MAX_BYTES:
        raise ValueError("too_large")
    img = Image.open(io.BytesIO(data))
    if img.format not in ALLOWED:
        raise ValueError("bad_format")
    img.verify()                          # structural check
    img = Image.open(io.BytesIO(data))    # verify() consumes the file object
    w, h = img.size
    if w * h > MAX_PIXELS or min(w, h) < 128:
        raise ValueError("bad_dimensions")
    return img.convert("RGB")             # drops EXIF and alpha
```

Three real risks this closes:

- **Decompression bomb** — a 40 KB PNG that decodes to 60,000 × 60,000 pixels
  and exhausts container memory. `Image.MAX_IMAGE_PIXELS` is Pillow's built-in
  guard; make sure it's set, not disabled.
- **Content-type spoofing** — trust the decoded format, never the declared
  MIME or the filename extension.
- **Malformed input reaching native code** — `verify()` before handing bytes to
  anything that compiles down to C.

Never let request data into a shell command. The current `cmd` heredoc is safe
because nothing is interpolated; keep that property. If you ever need a
filename in there, don't — pass it through the filesystem or an environment
variable instead.

### Layer 5 — resource ceilings

```python
@app.cls(
    gpu="L4",
    timeout=900,              # not 3600
    max_containers=4,         # bounds worst-case concurrent spend
    scaledown_window=300,
)
```

Then, outside the code:

- Set a **Modal spend limit / budget alert** on the workspace. This is the
  backstop for everything above — if all five layers fail, a hard cap turns a
  catastrophe into an incident.
- Alert on `model_jobs` insert rate exceeding a threshold per hour.
- Log `gpu_seconds` per job (the column exists in
  [02](02-cloud-database-schema.md)) and review the top consumers weekly.

## Content safety

Users are uploading arbitrary camera images to a service you operate and
storing the results. Two problems:

1. **Illegal or abusive content** in the `captures` bucket.
2. **Photos of people** — Hunyuan3D will happily generate a 3D model of a
   person who never consented.

Both are cheap to screen for. Run a classifier before the expensive pipeline —
this saves GPU time as well as risk:

- **NSFW**: `Falconsai/nsfw_image_detection` — small ViT classifier, runs in
  milliseconds on the same GPU, free on Hugging Face.
- **Faces**: any lightweight detector (MediaPipe, `face_recognition`). On a
  hit, either reject with "point the camera at an object, not a person" or
  proceed only with explicit acknowledgement. Rejecting is the safer default
  and fits the product — this feature is for artifacts, not portraits.

Log rejections with the user id. Repeat offenders get suspended.

## Secret handling

| Secret | Lives in | Never in |
| --- | --- | --- |
| Supabase `anon` key | The app (by design) | — |
| Supabase `service_role` key | Edge Function env, Modal Secret | The app, git, logs |
| Modal proxy key/secret | Supabase secrets | The app, git |
| LLM provider keys | Edge Function env | The app, git |

```bash
# Add before the first commit that touches these
echo ".env"            >> .gitignore
echo "**/.env.local"   >> .gitignore
echo "supabase/.env"   >> .gitignore
```

Run `gitleaks` or `trufflehog` over the history once. If a key was ever
committed, rotate it — removing the file doesn't remove it from the objects.

Note that `backend/hunyuan2.1/api_test.py` currently commits a live endpoint
URL. It's not a credential, but once proxy auth is on, that script needs the
headers, and the temptation will be to paste them in. Read them from the
environment instead.

## Testing checklist

- [ ] `curl` the Modal submit URL with no headers → 401 before any container starts
- [ ] Wrong proxy secret → 401
- [ ] Call the Edge Function with no `Authorization` → 401
- [ ] Call with an expired JWT → 401
- [ ] Submit `image_path` belonging to another user → 403
- [ ] Exhaust the daily quota → 429, no job created, no GPU time spent
- [ ] 20 parallel requests with 1 credit remaining → exactly one job created
- [ ] 40 MB upload → rejected at the bucket
- [ ] Decompression-bomb PNG → rejected before the pipeline
- [ ] `.exe` renamed to `.jpg` → rejected at decode
- [ ] `strings` over the release APK → no Modal URL, no service key
- [ ] Modal budget alert fires in a staging test
