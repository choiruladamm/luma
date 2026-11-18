import { createMiddleware } from "hono/factory";
import { findSessionUser } from "../auth/session";
import type { AppEnv } from "../env";
import { ApiError } from "../lib/errors";

/** Bearer token → user. No valid session → 401 (the client shows the "Login lagi" banner). */
export const requireSession = createMiddleware<AppEnv>(async (c, next) => {
  const user = await findSessionUser(c.var.db, c.req.header("authorization"));
  if (!user) throw new ApiError(401, "UNAUTHORIZED", "Sign in required");
  c.set("user", user);
  await next();
});
