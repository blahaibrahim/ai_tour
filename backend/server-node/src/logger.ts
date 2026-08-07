/**
 * Minimal stand-in for Python's `logging`, with the same per-module naming so
 * log lines stay greppable across the port. Deliberately not a dependency:
 * the Python side configured nothing beyond a stdout handler either.
 */
type Level = "debug" | "info" | "warning" | "error";

const ORDER: Record<Level, number> = { debug: 10, info: 20, warning: 30, error: 40 };

const threshold = ORDER[(process.env.LOG_LEVEL as Level) || "info"] ?? ORDER.info;

function emit(level: Level, name: string, args: unknown[]): void {
  if (ORDER[level] < threshold) return;
  const line = `[${level.toUpperCase()}] ${name} -`;
  if (level === "error" || level === "warning") console.error(line, ...args);
  else console.log(line, ...args);
}

export interface Logger {
  debug(...args: unknown[]): void;
  info(...args: unknown[]): void;
  warning(...args: unknown[]): void;
  error(...args: unknown[]): void;
  /** Python's `logger.exception` — an error line that includes the stack. */
  exception(message: string, error?: unknown): void;
}

export function getLogger(name: string): Logger {
  return {
    debug: (...args) => emit("debug", name, args),
    info: (...args) => emit("info", name, args),
    warning: (...args) => emit("warning", name, args),
    error: (...args) => emit("error", name, args),
    exception: (message, error) =>
      emit("error", name, [message, error instanceof Error ? error.stack : error]),
  };
}
