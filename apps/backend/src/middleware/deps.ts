import { createMiddleware } from "hono/factory";
import { openRouterAdmin } from "@luma/core/openrouter";
import { createDb } from "@luma/core/db/client";
import type { AppEnv } from "../env";

/**
 * Per-request dependencies on `c.var` (Drizzle `db`, `openrouter`), assembled
 * once here instead of in every handler. Cheap: just wrapper objects, no
 * query or subrequest yet.
 */
export const deps = createMiddleware<AppEnv>(async (c, next) => {
  c.set("db", createDb(c.env.DB));
  c.set("openrouter", openRouterAdmin(c.env.OPENROUTER_MANAGEMENT_KEY));
  await next();
});
