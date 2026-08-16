import { spawn, type ChildProcess } from "node:child_process";
import { EventEmitter } from "node:events";
import path from "node:path";

import {
  AUTO_FETCH_SPLATS,
  MAX_LOG_LINES,
  MODAL_BIN,
  MODAL_ENV,
  PIPELINE_DIR,
  SPLAT_CACHE_DIR,
  VOLUME_NAME,
} from "./config";
import {
  estimate,
  touchesGpu,
  type Quality,
  type SceneType,
  type Stage,
} from "./pipeline";
import { fetchSplat, listPath, sceneStatus } from "./volume";
import { absolutePathOf, resolveVideo } from "./videos";

export type JobStatus = "queued" | "running" | "succeeded" | "failed" | "canceled";

export interface LogLine {
  stream: "out" | "err" | "sys";
  text: string;
}

export interface Job {
  id: string;
  video: string;
  scene: string;
  sceneType: SceneType;
  quality: Quality;
  stage: Stage;
  force: boolean;
  reupload: boolean;
  status: JobStatus;
  createdAt: string;
  startedAt?: string;
  finishedAt?: string;
  estimateUsd: number;
  log: LogLine[];
  /** The `modal volume get ...` lines the entrypoint prints when it finishes. */
  artifacts: string[];
  error?: string;
}

export interface JobInput {
  video: string;
  sceneType: SceneType;
  quality: Quality;
  stage: Stage;
  force: boolean;
  reupload: boolean;
}

/**
 * In-memory job store, hung off `globalThis` so Next's dev-mode module reloads
 * don't orphan a running `modal` process. Restarting the server forgets the
 * history — that is fine, because the Volume is the durable record and every
 * stage output is cached there.
 */
interface Store {
  jobs: Map<string, Job>;
  children: Map<string, ChildProcess>;
  queue: string[];
  bus: EventEmitter;
  pumping: boolean;
}

const globalStore = globalThis as typeof globalThis & { __gsplat?: Store };

const store: Store = (globalStore.__gsplat ??= {
  jobs: new Map(),
  children: new Map(),
  queue: [],
  bus: new EventEmitter(),
  pumping: false,
});

store.bus.setMaxListeners(50);

export function subscribe(listener: () => void): () => void {
  store.bus.on("change", listener);
  return () => store.bus.off("change", listener);
}

function changed() {
  store.bus.emit("change");
}

export function listJobs(): Job[] {
  return [...store.jobs.values()].sort((a, b) =>
    b.createdAt.localeCompare(a.createdAt),
  );
}

export function getJob(id: string): Job | undefined {
  return store.jobs.get(id);
}

function log(job: Job, stream: LogLine["stream"], text: string) {
  job.log.push({ stream, text });
  if (job.log.length > MAX_LOG_LINES) {
    job.log.splice(0, job.log.length - MAX_LOG_LINES);
  }
  // The entrypoint prints the exact fetch command for every .ply it wrote —
  // including the odd step number a budget-truncated run ends on, which is why
  // this is scraped rather than reconstructed from the requested iterations.
  const artifact = text.match(/modal volume get \S+ \S+/);
  if (artifact) job.artifacts.push(artifact[0]);
  changed();
}

export async function createJob(input: JobInput): Promise<Job> {
  const video = await resolveVideo(input.video);
  if (!video) throw new Error(`no such video: ${input.video}`);

  const busy = [...store.jobs.values()].find(
    (job) =>
      job.scene === video.scene &&
      (job.status === "running" || job.status === "queued"),
  );
  if (busy) {
    throw new Error(
      `${video.scene} already has a ${busy.status} run — two runs on one scene ` +
        "would race on the same Volume paths",
    );
  }

  const preset = input.quality === "high" ? 30_000 : 7_000;
  const job: Job = {
    id: `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`,
    video: video.file,
    scene: video.scene,
    sceneType: input.sceneType,
    quality: input.quality,
    stage: input.stage,
    force: input.force,
    reupload: input.reupload,
    status: "queued",
    createdAt: new Date().toISOString(),
    estimateUsd: estimate(input.stage, input.quality, preset).total,
    log: [],
    artifacts: [],
  };

  store.jobs.set(job.id, job);
  store.queue.push(job.id);
  changed();
  void pump();
  return job;
}

export function cancelJob(id: string): boolean {
  const job = store.jobs.get(id);
  if (!job) return false;

  if (job.status === "queued") {
    store.queue = store.queue.filter((queued) => queued !== id);
    job.status = "canceled";
    job.finishedAt = new Date().toISOString();
    log(job, "sys", "canceled before it started");
    return true;
  }
  if (job.status === "running") {
    // Kills the local Modal client. Anything already scheduled on Modal keeps
    // running until it notices — check `modal app list` if you need certainty.
    store.children.get(id)?.kill();
    log(job, "sys", "sent kill to the modal client");
    return true;
  }
  return false;
}

/** One job at a time: the GPU stage is capped at one container anyway, and
 *  serialising here is what stops a stray double-click from double-spending. */
async function pump() {
  if (store.pumping) return;
  store.pumping = true;
  try {
    while (store.queue.length > 0) {
      const id = store.queue.shift()!;
      const job = store.jobs.get(id);
      if (!job || job.status !== "queued") continue;
      await run(job);
    }
  } finally {
    store.pumping = false;
  }
}

async function run(job: Job) {
  job.status = "running";
  job.startedAt = new Date().toISOString();
  changed();

  try {
    const video = await resolveVideo(job.video);
    if (!video) throw new Error(`${job.video} is no longer in the videos folder`);

    const ext = path.extname(video.file).toLowerCase();
    const remote = `/raw/${job.scene}${ext}`;

    const raw = await listPath("/raw");
    const alreadyUploaded = raw.entries.some((entry) =>
      path.posix.basename(entry.filename).startsWith(`${job.scene}.`),
    );

    if (alreadyUploaded && !job.reupload) {
      log(job, "sys", `${remote} is already in ${VOLUME_NAME} — skipping upload`);
    } else {
      log(job, "sys", `uploading ${video.file} to ${VOLUME_NAME}${remote}`);
      await exec(
        job,
        MODAL_BIN,
        [
          "volume",
          "put",
          VOLUME_NAME,
          absolutePathOf(video),
          remote,
          ...(alreadyUploaded ? ["--force"] : []),
        ],
        process.cwd(),
      );
    }

    const args = [
      "run",
      "modal_app.py",
      "--scene-name",
      job.scene,
      "--scene",
      job.sceneType,
      "--quality",
      job.quality,
      "--stage",
      job.stage,
      ...(job.force ? ["--force"] : []),
      // The CLI refuses to start the GPU stage without this, and the dashboard
      // only sends it for a stage that actually reaches training.
      ...(touchesGpu(job.stage) ? ["--yes"] : []),
    ];
    log(job, "sys", `${MODAL_BIN} ${args.join(" ")}`);
    await exec(job, MODAL_BIN, args, PIPELINE_DIR);

    job.status = "succeeded";
    await collect(job);
  } catch (err) {
    // A killed process lands here too; report it as the cancel it was.
    job.status = store.children.get(job.id)?.killed ? "canceled" : "failed";
    job.error = (err as Error).message;
    log(job, "sys", job.error);
  } finally {
    store.children.delete(job.id);
    job.finishedAt = new Date().toISOString();
    changed();
  }
}

/**
 * Copy whatever point clouds the run produced onto this machine.
 *
 * The Volume is still the durable record; this is what makes the result
 * *openable* without a second deliberate step — the dashboard's viewer reads
 * the local file, and so does anything else you want to drop it on.
 *
 * Deliberately never fails the job. The expensive, irreversible part already
 * succeeded by the time this runs: a download that did not work is a nuisance
 * you can retry from the splat card for free, not a run to mark as failed.
 */
async function collect(job: Job) {
  if (!AUTO_FETCH_SPLATS) return;

  try {
    const status = await sceneStatus(job.scene);
    const pending = status.plys.filter((ply) => !ply.cached);
    if (pending.length === 0) return;

    for (const ply of pending) {
      log(job, "sys", `fetching ${ply.name} (${ply.size}) to ${SPLAT_CACHE_DIR}`);
      try {
        log(job, "sys", `saved ${await fetchSplat(job.scene, ply.name)}`);
      } catch (err) {
        log(
          job,
          "sys",
          `could not fetch ${ply.name}: ${(err as Error).message} — it is still ` +
            `in the Volume, and the splat card can retry it`,
        );
      }
    }
  } catch (err) {
    log(job, "sys", `could not list the scene output: ${(err as Error).message}`);
  }
}

function exec(
  job: Job,
  bin: string,
  args: string[],
  cwd: string,
): Promise<void> {
  return new Promise((resolve, reject) => {
    // No shell: every argument here is either a fixed literal or a sanitised
    // scene name, and keeping the shell out means it can stay that way.
    const child = spawn(bin, args, {
      cwd,
      windowsHide: true,
      env: { ...process.env, ...MODAL_ENV },
    });
    store.children.set(job.id, child);

    pipe(child.stdout, (line) => log(job, "out", line));
    pipe(child.stderr, (line) => log(job, "err", line));

    child.on("error", (err) => {
      reject(
        (err as NodeJS.ErrnoException).code === "ENOENT"
          ? new Error(
              `could not run '${bin}' — install the Modal client or set ` +
                "MODAL_BIN to its full path",
            )
          : err,
      );
    });
    child.on("close", (code, signal) => {
      if (signal) return reject(new Error(`stopped by ${signal}`));
      if (code !== 0) return reject(new Error(`${bin} exited with code ${code}`));
      resolve();
    });
  });
}

/** Split a stream into lines, holding the partial tail until it completes. */
function pipe(
  stream: NodeJS.ReadableStream | null,
  onLine: (line: string) => void,
) {
  if (!stream) return;
  let buffer = "";
  stream.setEncoding("utf8");
  stream.on("data", (chunk: string) => {
    buffer += chunk;
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() ?? "";
    for (const line of lines) onLine(line);
  });
  stream.on("end", () => {
    if (buffer) onLine(buffer);
  });
}
