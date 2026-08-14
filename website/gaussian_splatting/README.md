# Splat Studio

A dashboard for `backend/gaussian_splatting`. Lists the clips on your machine,
plays them, and starts the Modal pipeline on the one you pick — with the cost
estimate on screen before the button does anything.

It is a front end for the `modal` CLI and nothing else. Every run is the same
`modal run modal_app.py …` you would have typed, spawned as a child process with
its output streamed back to the page. There is no second implementation of any
stage here, and no Modal API calls of its own: whatever profile your CLI is
already logged into is the one that gets billed.

```
videos/plaza.mp4 ──▶ modal volume put ──▶ modal run modal_app.py ──▶ .ply in the Volume
     (local)              /raw/                 frames → sfm → train
```

## Run it

```bash
npm install
npm run dev          # http://localhost:3000
```

Drop clips into `videos/` (git-ignored — a capture is hundreds of MB) and
reload. The filename stem becomes the scene name: `Old Medina.mp4` → `old_medina`
→ `/raw/old_medina.mp4` in the Volume.

The Modal client must be installed and logged in:

```bash
pip install -r ../../backend/gaussian_splatting/requirements-local.txt
modal token new
```

Copy `.env.example` to `.env.local` to point at a different videos folder,
pipeline checkout or Volume. On Windows, if `next dev` cannot find `modal` on
PATH, set `MODAL_BIN` to its full path.

## What the controls do

Each maps to one flag on the CLI — see the pipeline's own README for what they
mean for reconstruction quality.

| Control | Flag |
|---|---|
| Scene — outdoor / indoor | `--scene` |
| Quality — draft / high | `--quality` (7k / 30k iterations) |
| Stage — frames / SfM / train / all | `--stage` |
| Redo cached stages | `--force` |
| Re-upload the clip | `modal volume put --force` |

Two things happen before a run: the clip is uploaded to `/raw` if it isn't there
already, and the panel reads the Volume to see which stages are already cached.
Cached stages are skipped by the CLI, so they are also left out of the estimate —
re-running training on a scene that already has SfM output shows the GPU cost
alone.

**A run that reaches the training stage asks twice.** The first press arms the
button and shows the total; the second starts it. That is this dashboard's
version of the CLI's `--yes` gate, and it exists for the same reason: nothing
else here can spend GPU money.

## What it does not do

- **No viewer.** Finished point clouds stay in the Volume; the job card prints
  the `modal volume get …` command for each `.ply`, which you drop on
  [superspl.at/editor](https://superspl.at/editor).
- **No job history.** Runs live in memory and are forgotten when the server
  restarts. The Volume is the durable record — every stage output is cached
  there, so a forgotten run costs nothing to pick back up.
- **One run at a time.** Queued, not parallel. The GPU stage is capped at one
  container anyway, and serialising is what stops a double-click from
  double-spending.
- **Cancel stops the local client**, not necessarily the container it started.
  Check `modal app list` if you need to be sure.

## Layout

```
app/
  page.tsx                    renders the dashboard
  api/videos/                 list clips; stream one with byte ranges
  api/volume/                 what is in the Volume, for the badges
  api/scenes/[scene]/         which stages are cached, for the estimate
  api/jobs/                   list, start, cancel
  api/jobs/events/            one SSE stream carrying every job and its log
components/                   Dashboard, VideoCard, RunPanel, JobCard, …
lib/
  pipeline.ts                 presets, cost model, scene naming (browser + server)
  config.ts                   paths and binaries, all env-overridable
  videos.ts                   the local videos folder
  volume.ts                   `modal volume ls` wrappers
  jobs.ts                     the job store and the child processes
```

`lib/pipeline.ts` mirrors the presets and Modal's rates from `modal_app.py`,
which stays the source of truth. If a preset changes there, change it here too —
the only thing that goes wrong is that the estimate stops matching the one the
CLI prints.

## Design

The palette, radii, spacing scale and motion tokens in `app/globals.css` are
copied from the Flutter app's `lib/theme.dart` — same "Fennec Compass" colors,
same 4pt scale, same flat fills and soft navy-tinted shadows. `SegmentedControl`
is the web twin of `lib/widgets/segmented_control.dart`: a bounded track with a
sliding indicator, for choices that are few, fixed and mutually exclusive.

## Status

The dashboard's own plumbing is tested — listing, playback with byte ranges,
job lifecycle, log streaming, cancel. **The Modal side has never been run**, by
this dashboard or by anything else; the pipeline's README says so too. Start
where its verification ladder starts, from a terminal:

```bash
cd ../../backend/gaussian_splatting
modal run modal_app.py --stage build
```

Then use the dashboard for the stages that follow.
