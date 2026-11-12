import { createMiddleware } from "hono/factory";
import type { AppEnv } from "../env";

export const requestId = createMiddleware<AppEnv>(async (c, next) => {
  const id = crypto.randomUUID();
  c.set("requestId", id);
  c.header("x-request-id", id);
  await next();
});
