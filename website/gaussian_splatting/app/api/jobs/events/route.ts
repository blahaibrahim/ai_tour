import { listJobs, subscribe, type Job } from "@/lib/jobs";

export const dynamic = "force-dynamic";

/** Lines of a job's log pushed to the browser. The full buffer stays server-side. */
const LOG_TAIL = 500;

function payload(): string {
  const jobs: Job[] = listJobs().map((job) => ({
    ...job,
    log: job.log.slice(-LOG_TAIL),
  }));
  return `data: ${JSON.stringify({ jobs })}\n\n`;
}

/**
 * One stream for every job, rather than one per job: the dashboard only ever
 * renders the whole list, and a single connection means no per-job wiring to
 * open, close and reconnect.
 */
export async function GET(request: Request) {
  const encoder = new TextEncoder();

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      let closed = false;
      let pending: NodeJS.Timeout | null = null;

      const send = (text: string) => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(text));
        } catch {
          closed = true;
        }
      };

      // Coalesced: a chatty stage emits log lines far faster than anything
      // needs to repaint.
      const schedule = () => {
        if (pending || closed) return;
        pending = setTimeout(() => {
          pending = null;
          send(payload());
        }, 200);
      };

      send(payload());
      const unsubscribe = subscribe(schedule);
      const heartbeat = setInterval(() => send(": ping\n\n"), 25_000);

      const stop = () => {
        if (closed) return;
        closed = true;
        unsubscribe();
        clearInterval(heartbeat);
        if (pending) clearTimeout(pending);
        try {
          controller.close();
        } catch {
          // Already closed by the client going away.
        }
      };

      request.signal.addEventListener("abort", stop);
    },
  });

  return new Response(stream, {
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-cache, no-transform",
      connection: "keep-alive",
    },
  });
}
