import { createApp } from "./app";
import { Config } from "./config";
import { getLogger } from "./logger";

const logger = getLogger("index");

const app = createApp();

app.listen(Config.PORT, "0.0.0.0", () => {
  logger.info(`listening on http://0.0.0.0:${Config.PORT}`);
});

// A rejected promise nobody handled must not take the process down mid-route.
// The Python equivalent was a thread dying quietly; this at least says so.
process.on("unhandledRejection", (reason) => {
  logger.exception("Unhandled promise rejection", reason);
});
