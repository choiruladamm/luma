import { createMiddleware } from "hono/factory";
import { openRouterAdmin } from "../clients/openrouter";
import { createDb } from "../db/client";
import type { AppEnv } from "../env";

/**
 * Dependency per request di `c.var` (`db` Drizzle, `openrouter`), dirakit
 * sekali di sini, bukan di tiap handler. Murah: cuma objek pembungkus, belum
 * ada query / subrequest.
 */
export const deps = createMiddleware<AppEnv>(async (c, next) => {
  c.set("db", createDb(c.env.DB));
  c.set("openrouter", openRouterAdmin(c.env.OPENROUTER_MANAGEMENT_KEY));
  await next();
});
