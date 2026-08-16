# Massar Studio

The operations dashboard for the tour project: what is in the catalogue, what
explorers have captured in it, and the Gaussian splats trained from that
footage. Two views.

| Tab | What it is |
|---|---|
| **Overview** | Analytics read live out of Supabase — explorers, stops, routes, captures, model jobs, storage — plus the splat pipeline's own funnel. |
| **Studio** | Where a capture is on one side, what splatting has made of it on the other. Left: wilaya → its stops → the footage recorded at a stop. Right: the selected clip's player, its cached stages, the cost of the run, the live log, and the splat itself. |

The map and the runs used to be separate tabs, which meant picking a clip on a
map and then losing the map to go and run it. One selection now drives both
halves, and it lives in the URL, so a clip or a splat can be linked to:
`#studio/16/<poi-id>/<clip>/point_cloud_7000.ply`.

```
videos/plaza.mp4 ──▶ modal volume put ──▶ modal run modal_app.py ──▶ .ply in the Volume ──▶ viewer
     (local)              /raw/                 frames → sfm → train        modal volume get
```

Everything that spends money is still a `modal` child process — there is no
second implementation of any stage here and no Modal API calls of its own.
Whatever profile your CLI is logged into is the one that gets billed.

## Run it

```bash
npm install
cp .env.example .env.local     # then fill in the two Supabase values
npm run dev                    # http://localhost:3000
```

**`SUPABASE_SERVICE_ROLE_KEY`, not the anon key.** The numbers this dashboard
shows — every explorer's captures, every model job, storage usage — are exactly
what RLS hides from `anon`. Neither variable is `NEXT_PUBLIC_`: the key is read
server-side only, and the browser gets aggregates and short-lived signed URLs.
The consequence is that **this is a local tool**, not something to deploy
publicly. Without the pair, the Overview tab and the Studio's left half come up
empty with a banner saying so; the run controls are unaffected.

Drop clips into `videos/` (git-ignored — a capture is hundreds of MB). The
filename stem becomes the scene name: `Old Medina.mp4` → `old_medina` →
`/raw/old_medina.mp4` in the Volume.

The Modal client must be installed and logged in for the run controls and the
Volume chip:

```bash
pip install -r ../../backend/gaussian_splatting/requirements-local.txt
modal token new
```

On Windows, if `next dev` cannot find `modal` on PATH, set `MODAL_BIN` to its
full path.

## The map, and one thing the schema cannot answer

Stops come from `pois`; which wilaya each one is in is decided server-side by
point-in-polygon against `public/dz_wilayas.geojson` — the same file the
Flutter app draws its map from, so the two surfaces can never disagree about
where a boundary is.

The map pans and zooms — scroll to zoom about the cursor, drag to pan,
double-click a wilaya to fit it, `⌂` to reset — because everything catalogued
so far sits in three coastal wilayas and Alger is about eight pixels wide at
national scale. Zooming moves the `viewBox` rather than transforming a group,
so the projection, the hit targets and the tooltip all stay in one coordinate
space; strokes carry `vector-effect: non-scaling-stroke` so the hairline
between wilayas doesn't swallow the small ones at 40×.

**Which stop a clip is a recording of is not in the database.**
`artifacts.location_id` points at `locations`, the discovery-pipeline
catalogue, which is empty — while the map, the routes and this dashboard all
run on `pois`. So the link is dashboard-owned and local, in
`videos/assignments.json`, set from the Studio's footage panel:

```json
{
  "clips": { "casbah_orbit.mp4": "<poi uuid>" },
  "artifacts": { "<artifact uuid>": "<poi uuid>" }
}
```

Additive and reversible. The durable fix is an `artifacts.poi_id` column, and
it belongs in a migration alongside the app change that starts writing it — not
in a dashboard. The day it exists, `lib/assignments.ts` is deleted rather than
migrated.

## The splat viewer

**A finished run saves its point clouds onto this machine automatically**, into
`.splats/<scene>/` (git-ignored — the Volume is still the durable copy, so
deleting it only means fetching again). The download is logged in the run's own
output, and a failed download never fails the run: the expensive part already
succeeded, and the splat card can retry it for free. Set `GSPLAT_AUTO_FETCH=0`
to keep results in the Volume only.

Anything not already local gets a **fetch** button on the splat card, which
runs the same `modal volume get`. **View** then renders it in the browser with
no dependencies: `lib/splat.ts` reads the INRIA format and
`components/SplatCanvas.tsx` is a ~300-line WebGL2 renderer. Drag to orbit,
shift-drag to pan, scroll to zoom.

It draws each gaussian as a screen-space disc, sized by its own scale, with a
gaussian falloff, depth-sorted back-to-front every time the camera moves far
enough. That is the cheap half of splatting — the real rasteriser projects each
gaussian's 3D covariance to an oriented 2D ellipse, so a thin surface reads as
a thin surface rather than a round dab. The difference shows on flat walls and
at grazing angles. This is a "did the capture reconstruct" view; for the full
render, drop the fetched `.ply` on [superspl.at/editor](https://superspl.at/editor).

A splat already fetched stays viewable with no Modal client and no network —
the local copy is a real file and the viewer needs nothing else.

## What the Run controls do

Each maps to one flag on the CLI — see the pipeline's own README for what they
mean for reconstruction quality.

| Control | Flag |
|---|---|
| Scene — outdoor / indoor | `--scene` |
| Quality — draft / high | `--quality` (7k / 30k iterations) |
| Stage — frames / SfM / train / all | `--stage` |
| Redo cached stages | `--force` |
| Re-upload the clip | `modal volume put --force` |

Two things happen before a run: the clip is uploaded to `/raw` if it isn't
there already, and the panel reads the Volume to see which stages are already
cached. Cached stages are skipped by the CLI, so they are also left out of the
estimate — re-running training on a scene that already has SfM output shows the
GPU cost alone.

**A run that reaches the training stage asks twice.** The first press arms the
button and shows the total; the second starts it. That is this dashboard's
version of the CLI's `--yes` gate, and it exists for the same reason: nothing
else here can spend GPU money.

## What it does not do

- **No job history.** Runs live in memory and are forgotten when the server
  restarts. The Volume is the durable record — every stage output is cached
  there, so a forgotten run costs nothing to pick back up.
- **One run at a time.** Queued, not parallel. The GPU stage is capped at one
  container anyway, and serialising is what stops a double-click from
  double-spending.
- **Cancel stops the local client**, not necessarily the container it started.
  Check `modal app list` if you need to be sure.
- **No GLB preview.** A finished 3D model from the app's own Hunyuan pipeline
  shows its capture photo and a download link; only splats get a viewer. Adding
  `<model-viewer>` would be the first runtime dependency in the project.
- **No writes to Supabase.** Every read is `select`; the only thing this
  dashboard writes is `videos/assignments.json`.
- **Storage sizes need one setting.** The Storage card reads `storage.objects`
  through PostgREST, which needs the `storage` schema exposed to the Data API
  (Project Settings > API). Without it that one card is empty and nothing else
  is affected.

## Layout

```
app/
  page.tsx                    renders the dashboard
  api/analytics/              everything the Overview shows, in one read
  api/atlas/                  wilayas + stops + capture counts
  api/atlas/pois/[id]/        one stop's footage, with signed storage URLs
  api/assignments/            attach a clip or a capture to a stop
  api/scenes/[scene]/         which stages are cached, for the estimate
  api/scenes/[scene]/splat/[name]/   POST fetches a .ply, GET serves it
  api/videos/                 list clips; stream one with byte ranges
  api/volume/                 what is in the Volume, for the badges
  api/jobs/                   list, start, cancel
  api/jobs/events/            one SSE stream carrying every job and its log
components/
  Dashboard                   the shell: brand, tabs, Volume chip
  Overview, Charts            the analytics view and its chart vocabulary
  Studio                      the merged view; owns the selection and the jobs
  AlgeriaMap                  the pan/zoom wilaya choropleth
  SplatCanvas                 the WebGL2 splat renderer
  VideoCard, RunPanel, JobCard, SegmentedControl, StatusPill
lib/
  supabase.ts                 PostgREST + Storage over fetch; no client library
  analytics.ts                the Overview's aggregation
  atlas.ts                    wilaya -> stops -> footage
  wilayas.ts                  the GeoJSON and point-in-polygon
  assignments.ts              the clip -> stop link, and why it is a file
  splat.ts                    the INRIA .ply reader
  pipeline.ts                 presets, cost model, scene naming (browser + server)
  config.ts                   paths, binaries and keys, all env-overridable
  videos.ts                   the local videos folder
  volume.ts                   `modal volume ls/get` wrappers
  jobs.ts                     the job store and the child processes
```

`lib/pipeline.ts` mirrors the presets and Modal's rates from `modal_app.py`,
which stays the source of truth. If a preset changes there, change it here too —
the only thing that goes wrong is that the estimate stops matching the one the
CLI prints.

## Design

The palette, radii, spacing scale and motion tokens in `app/globals.css` are
copied from the Flutter app's `lib/theme.dart` — same "Fennec Compass" colors,
same 4pt scale, same flat fills and soft navy-tinted shadows. The mark in the
header is the app's own icon.

Every quantity on the Overview is a *magnitude* — how many stops in a category,
how many captures a week, how far a scene got — so there is deliberately no
categorical palette: one hue, and one ordered ramp of it for the pipeline
funnel and the wilaya map. The ramp's steps are validated rather than picked by
eye (monotone OKLCH lightness, every adjacent gap ≥ 0.06, the light end at
2.33:1 on white). Every value is directly labelled, so nothing on the page is
readable only by comparing two fills.

## Status

The dashboard's own plumbing is exercised — listing, playback with byte ranges,
job lifecycle, log streaming, cancel, the Supabase reads, the wilaya assignment,
storage URL signing, and the splat viewer against a synthetic `.ply`. **The
Modal side has never been run**, by this dashboard or by anything else; the
pipeline's README says so too. Start where its verification ladder starts, from
a terminal:

```bash
cd ../../backend/gaussian_splatting
modal run modal_app.py --stage build
```

Then use the dashboard for the stages that follow.
