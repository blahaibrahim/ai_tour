/**
 * The concurrency primitives this port needs in place of Python's
 * `concurrent.futures` / `threading`.
 *
 * Every pool in the Flask server wrapped HTTP I/O, never CPU work, so the
 * thread pools become plain promises plus a semaphore. Two consequences worth
 * knowing:
 *
 *   * Promises are eager. `pool.submit(fn)` and `fn()` both start the work
 *     immediately, so a "future" here is just the promise — but an eagerly
 *     started promise that nobody awaits in time would raise an unhandled
 *     rejection, which `settle()` and `awaitWithin()` guard against.
 *   * There are no locks. The JWT cache and the Overpass bbox cache were
 *     `threading.Lock`-guarded dicts; a single-threaded event loop makes both
 *     plain Maps with the same guarantees.
 */

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * A `ThreadPoolExecutor(max_workers=n)` equivalent: caps how many wrapped
 * tasks run at once, queueing the rest in submission order.
 */
export function createLimiter(concurrency: number): <T>(fn: () => Promise<T>) => Promise<T> {
  let active = 0;
  const queue: Array<() => void> = [];

  const release = (): void => {
    active--;
    const next = queue.shift();
    if (next) next();
  };

  return <T>(fn: () => Promise<T>): Promise<T> =>
    new Promise<T>((resolve, reject) => {
      const run = (): void => {
        active++;
        void (async () => {
          try {
            resolve(await fn());
          } catch (error) {
            reject(error);
          } finally {
            release();
          }
        })();
      };
      if (active < concurrency) run();
      else queue.push(run);
    });
}

/**
 * Await a promise but never longer than `ms`, and never throw — `null` covers
 * both the timeout and the failure, which is exactly what
 * `future.result(timeout=...)` wrapped in `except Exception: None` did.
 *
 * The rejection is swallowed at attach time, so a slow photo lookup that fails
 * after the route has already been sent cannot crash the process.
 */
export function awaitWithin<T>(promise: Promise<T>, ms: number): Promise<T | null> {
  return new Promise<T | null>((resolve) => {
    let done = false;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      resolve(null);
    }, Math.max(0, ms));

    promise.then(
      (value) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(value);
      },
      () => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(null);
      },
    );
  });
}

/** A promise that can be inspected without awaiting it, and never rejects. */
export interface Settled<T> {
  readonly promise: Promise<{ ok: true; value: T } | { ok: false; error: unknown }>;
  readonly isDone: () => boolean;
}

export function settle<T>(promise: Promise<T>): Settled<T> {
  let done = false;
  const wrapped = promise.then(
    (value) => {
      done = true;
      return { ok: true as const, value };
    },
    (error) => {
      done = true;
      return { ok: false as const, error };
    },
  );
  return { promise: wrapped, isDone: () => done };
}

/** `time.monotonic()`-based deadline, for budgets shared across several awaits. */
export class Deadline {
  private readonly endsAt: number;

  constructor(ms: number) {
    this.endsAt = Date.now() + ms;
  }

  remainingMs(): number {
    return Math.max(0, this.endsAt - Date.now());
  }
}

/**
 * Resolves as soon as any of `promises` settles, or after `ms`. Returns the
 * settled ones. Mirrors `concurrent.futures.wait(..., FIRST_COMPLETED)`, which
 * the Overpass hedging loop is built on.
 */
export async function waitFirst<T>(
  settled: Array<Settled<T>>,
  ms: number,
): Promise<Array<Settled<T>>> {
  if (settled.length === 0) return [];
  const alreadyDone = settled.filter((s) => s.isDone());
  if (alreadyDone.length > 0) return alreadyDone;

  const timeout = new Promise<void>((resolve) => {
    const timer = setTimeout(resolve, Math.max(0, ms));
    // Never hold the process open for a hedge window nobody is waiting on.
    if (typeof timer.unref === "function") timer.unref();
  });

  await Promise.race([...settled.map((s) => s.promise), timeout]);
  return settled.filter((s) => s.isDone());
}
