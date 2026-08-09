# 14 — AR Capture Module: Database Setup via the Supabase CLI

> **Status:** New. Written because the Supabase MCP connection dropped mid-session
> and couldn't apply the migration live — this is the manual equivalent. Assumes
> the target database is **empty** (no `locations`, `pois`, `routes`, etc.).

This walks through applying the AR capture module's schema with the Supabase
CLI directly, no MCP required. It creates the *route generation* schema
(`backend/server-node/sql/001_route_generation.sql`) and the *AR capture*
schema (`backend/server-node/sql/002_ar_capture.sql`) that builds on top of
it — `002` cannot be applied without `001`, since `ar_contents.poi_id`,
`mascot_spawns.route_id` etc. are real foreign keys into `001`'s tables.

Design rationale for both files lives in `backend/server-node/src/routeGeneration/README.md`
and `backend/server-node/src/arCapture/README.md`. This doc is only the "how
do I get the tables to exist" half.

**What this does *not* do:** make the AR capture endpoints fully live. Both
Node modules' Data layers (`src/routeGeneration/data/`, `src/arCapture/data/`)
are still stubs — every repository method throws `NotImplementedError`. This
migration gets the schema in place so that work can start; it's Data-layer
implementation, not this doc, that turns `AR_CAPTURE_MODE=real` into
something that actually answers requests.

**Every command below is run from `backend/server-node/`** (step A2/B3 `cd`
there and nothing after it changes directory again) — that keeps `--file
sql/...` paths short and keeps `supabase init` from touching the repo root's
`supabase/` folder, which is the real project's own migration ledger and
should stay untouched by any of this.

---

## Prerequisites

- Node.js (already required by `backend/server-node` — see its `package.json`).
  The Supabase CLI is run via `npx supabase`, no global install needed.
- **One** of:
  - **Docker Desktop**, running, for a local Postgres you fully control (Option A —
    recommended for a first pass, since nothing here touches a shared project).
  - A **Supabase personal access token** and an **empty** Supabase project, for
    applying directly to the cloud (Option B).

---

## Option A — Local Postgres via Docker (recommended)

This spins up an isolated local Supabase stack. It never touches your real
project, so there's nothing to get wrong.

### A1. Start Docker Desktop

Launch it normally and wait until it reports "Docker Desktop is running."
Verify from a terminal:

```bash
docker info
```

If that errors with something like `failed to connect to the docker API`,
Docker isn't up yet — wait and retry.

### A2. Initialize a scratch Supabase project for this

```bash
cd backend/server-node
npx supabase init --force
```

(`--force` only matters if you re-run this later; it overwrites a stale
`backend/server-node/supabase/config.toml`, nothing else. Everything from
here on assumes you stay in this directory.)

### A3. Start the local stack

```bash
npx supabase start
```

First run pulls several Docker images — a few minutes. When it finishes it
prints a block like:

```
API URL: http://127.0.0.1:54321
DB URL: postgresql://postgres:postgres@127.0.0.1:54322/postgres
Studio URL: http://127.0.0.1:54323
...
```

`Studio URL` is a local web UI (like the Supabase dashboard) if you want to
click through the tables afterward instead of querying.

### A4. Apply the two SQL files, in order

```bash
npx supabase db query --local --file sql/001_route_generation.sql
npx supabase db query --local --file sql/002_ar_capture.sql
```

Each should finish with no output (success) or a summary of statements run.
If `002` errors about a missing relation (`pois` or `routes`), `001` didn't
finish cleanly — scroll up its output before retrying `002`.

### A5. Verify

```bash
npx supabase db query --local "select table_name from information_schema.tables where table_schema = 'public' order by 1;"
```

Expect to see `mascots`, `ar_contents`, `mascot_spawns`, `mascot_captures`,
`mascot_collection`, `push_tokens`, plus `001`'s `cities`, `categories`,
`pois`, `routes`, `route_stops`, `progress`, `progress_events`, `regions`.

```bash
npx supabase db query --local "select conname from pg_constraint where conname = 'fk_pois_ar_content';"
```

Expect one row — this is `002` closing the loop `001` left open
(`pois.ar_content_id → ar_contents.id`).

### A6. When you're done

```bash
npx supabase stop
```

Add `--no-backup` to also delete the local data volume, if you want a clean
slate next time rather than resuming where you left off.

---

## Option B — A real, empty Supabase project

Only do this against a project you're sure has nothing in it yet — this is a
schema change to shared infrastructure, not a local sandbox.

### B1. Get a personal access token

[supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens) →
Generate new token. Copy it.

### B2. Log in

```bash
npx supabase login --token <paste-the-token-here>
```

Or, without saving it to CLI config, export it for the session instead:

```bash
export SUPABASE_ACCESS_TOKEN=<paste-the-token-here>
```

### B3. Link this checkout to the project

Find the project ref in its dashboard URL:
`supabase.com/dashboard/project/<project-ref>`.

```bash
cd backend/server-node
npx supabase init --force
npx supabase link --project-ref <project-ref>
```

It will prompt for the database password (Project Settings → Database).
Everything from here on assumes you stay in this directory.

### B4. Apply the two SQL files, in order

```bash
npx supabase db query --linked --file sql/001_route_generation.sql
npx supabase db query --linked --file sql/002_ar_capture.sql
```

### B5. Verify

Same two checks as A5, with `--local` swapped for `--linked` — or just look
in the dashboard's Table Editor.

---

## After either option: configure the app

1. In `backend/.env`, set a real value for `AR_CAPTURE_TOKEN_SECRET` (any long
   random string — it signs capture tokens, see
   `src/arCapture/domain/captureToken.ts`). Already documented in
   `backend/.env.example`.
2. If you point `backend/server-node` at this database, its `SUPABASE_URL` /
   `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` in `backend/.env` need to
   match it (Option A's local stack prints its own anon/service_role keys in
   the `supabase start` output; Option B's are in the dashboard's API
   settings).
3. Leave `ROUTE_GENERATION_MODE` and `AR_CAPTURE_MODE` unset (both default to
   `fixture`) until the Data layer repositories are actually implemented —
   flipping either to `real` today just changes *which* `NotImplementedError`
   you see.

---

## Starting over

**Option A (local):** `npx supabase db reset` (run from `backend/server-node`)
replays `backend/server-node/supabase/migrations/` from scratch — but note
`001`/`002` were applied via `db query`, not as tracked migrations, so a
reset **won't** reapply them; it'll just give you an empty database again.
Re-run A4 afterward.

**Option B (remote) or a local DB you want to unwind without a full reset:**
run this against the same target, in this order (reverse of creation, so the
foreign keys don't block the drop):

```sql
drop table if exists push_tokens, mascot_collection, mascot_captures, mascot_spawns cascade;
alter table pois drop constraint if exists fk_pois_ar_content;
drop table if exists ar_contents, mascots cascade;
drop type if exists device_platform, placement_quality, capture_outcome, spawn_state, mascot_rarity;

drop table if exists progress_events, progress, route_stops, routes, pois, categories, cities, regions cascade;
drop type if exists transport_mode, progress_status, poi_status, poi_source, routing_provider, rollout_status;
```

You can run this with the same `db query` command, either piped inline or
saved to a file and passed with `--file`.
