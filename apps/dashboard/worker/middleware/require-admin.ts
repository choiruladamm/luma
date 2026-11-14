import { getSignedCookie } from "hono/cookie";
import { createDb } from "../../../backend/src/db/client";
import { isAdmin } from "../auth/admin";
import { findSession, sessionCookieName } from "../auth/session";
import { factory } from "../env";
import { ApiError } from "../lib/errors";

/**
 * Cookie session + admin check, global on `/api/*` (except `/api/auth/*`), so new
 * routes are protected automatically. The cookie signature is checked first: no
 * cookie / bad signature → 401 without touching D1. The Better Auth instance is
 * not built here (CPU-heavy); one join query is enough.
 */
export const requireAdmin = factory.createMiddleware(async (c, next) => {
  const token = await getSignedCookie(c, c.env.BETTER_AUTH_SECRET, sessionCookieName(c.env));
  if (!token) throw new ApiError(401, "UNAUTHORIZED", "Sign in required");

  const db = createDb(c.env.DB);
  const session = await findSession(db, token);
  if (!session || session.expiresAt.getTime() <= Date.now()) {
    throw new ApiError(401, "UNAUTHORIZED", "Sign in required");
  }
  // Rechecked every request: removing an email from ADMIN_EMAILS rejects its existing sessions at once.
  if (!isAdmin(c.env, session)) throw new ApiError(403, "FORBIDDEN", "Admin only");

  c.set("db", db);
  c.set("admin", { id: session.id, email: session.email });
  await next();
});
