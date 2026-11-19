import type { Hono } from "hono";
import { notFound, onError } from "./errors";
import { requestId } from "./middleware";

/**
 * The pipeline start every Worker shares: request id first, then JSON errors for unknown
 * routes and failures (docs/workers.md, Conventions). Register the Worker's own middleware after.
 */
// Any env and route schema: the caller's app type comes back unchanged for `AppType`.
export function workerApp<H extends Hono<any, any, any>>(app: H): H {
  app.use(requestId);
  app.notFound(notFound);
  app.onError(onError);
  return app;
}
