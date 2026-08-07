import express, { Express, NextFunction, Request, Response } from "express";

import { getLogger } from "./logger";
import { authRouter } from "./routes/auth";
import { chatRouter } from "./routes/chat";
import { healthRouter } from "./routes/health";
import { itineraryRouter } from "./routes/itinerary";
import { modelsRouter } from "./routes/models";
import { poiRouter } from "./routes/poi";
import { tasksRouter } from "./routes/tasks";

const logger = getLogger("app");

export function createApp(): Express {
  const app = express();

  // Flask's `request.get_json(silent=True) or {}` never raised on a malformed
  // or absent body, so neither does this: a bad body becomes `{}` and the
  // route's own validation produces the 400, rather than the parser doing it
  // with a different shape.
  app.use(express.json({ limit: "1mb" }));
  app.use((err: unknown, _req: Request, res: Response, next: NextFunction) => {
    if (err instanceof SyntaxError && "body" in err) {
      res.status(400).json({ error: "bad_request", message: "malformed JSON body" });
      return;
    }
    next(err);
  });

  app.use(healthRouter);
  app.use(itineraryRouter);
  app.use(chatRouter);
  app.use(tasksRouter);
  app.use(poiRouter);
  app.use(modelsRouter);
  app.use(authRouter);

  // Flask returned a 500 HTML page for an unhandled exception; this keeps the
  // JSON content type the client already expects from every other error.
  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    logger.exception("Unhandled error", err);
    if (res.headersSent) return;
    res.status(500).json({ error: "server_error" });
  });

  return app;
}
