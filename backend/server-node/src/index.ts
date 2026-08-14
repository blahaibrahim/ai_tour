import { createApp } from "./app";
import { Config } from "./config";
import { getLogger } from "./logger";
import { initCache } from "./routeGeneration/adapters/cacheAdapter";

const logger = getLogger("index");

const app = createApp();

// Decide the route cache backend before the first request rather than lazily
// inside it, so which one is in use — and why — is in the startup log instead
// of buried in whichever request happened to arrive first. Never rejects: no
// REDIS_URL, or a Redis that does not answer, both settle on in-memory.
void initCache();

app.listen(Config.PORT, "0.0.0.0", () => {
  logger.info(`listening on http://0.0.0.0:${Config.PORT}`);
});

// A rejected promise nobody handled must not take the process down mid-route.
// The Python equivalent was a thread dying quietly; this at least says so.
process.on("unhandledRejection", (reason) => {
  logger.exception("Unhandled promise rejection", reason);
});
