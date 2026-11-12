import { createMiddleware } from "hono/factory";
import { findSessionUser } from "../auth/session";
import { createDb } from "../db/client";
import type { AppEnv } from "../env";
import { ApiError } from "../lib/errors";

/** Bearer token → user. Tanpa sesi valid → 401 (client munculin banner "Login lagi"). */
export const requireSession = createMiddleware<AppEnv>(async (c, next) => {
  const user = await findSessionUser(createDb(c.env.DB), c.req.header("authorization"));
  if (!user) throw new ApiError(401, "UNAUTHORIZED", "Sign in required");
  c.set("user", user);
  await next();
});
