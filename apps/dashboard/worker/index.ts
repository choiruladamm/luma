import { getSignedCookie } from "hono/cookie";
import { createDb } from "@luma/core/db/client";
import { workerApp } from "@luma/worker-kit/app";
import { normalizeAuthError, notFound } from "@luma/worker-kit/errors";
import { limitBody } from "@luma/worker-kit/middleware";
import { getAuth } from "./auth/auth";
import { endSessionIfPastMaxAge, sessionCookieName } from "./auth/session";
import { factory } from "./env";
import { invites } from "./features/invites/routes";
import { overview } from "./features/overview/routes";
import { users } from "./features/users/routes";
import { rateLimitAdmin, rateLimitIp } from "./middleware/rate-limit";
import { requireAdmin } from "./middleware/require-admin";
import { requireSameOriginJson } from "./middleware/same-origin";
import { securityHeaders } from "./middleware/security-headers";

/** Better Auth endpoints exposed: only the Google redirect login. Everything else (sign-up, update-user, …) is 404. */
export const AUTH_ROUTES = [
  ["GET", "/api/auth/get-session"],
  ["POST", "/api/auth/sign-in/social"],
  ["GET", "/api/auth/callback/google"],
  ["POST", "/api/auth/sign-out"],
] as const;

/** Every dashboard body is a small JSON object (an invite count, a sign-in provider). */
const API_BODY_LIMIT = 16 * 1024;

// Order: requestId → IP rate limit → body limit → [/api/auth/* → Better Auth] → session + admin →
// mutation checks → route.
const app = workerApp(factory.createApp())
  .use(securityHeaders)
  .use("/api/*", rateLimitIp, limitBody(API_BODY_LIMIT));
// get-session is where Better Auth slides the session, so the 30-day cap goes in front of it:
// past the cap the row is gone and Better Auth answers "no session" (+1 query per call).
app.get("/api/auth/get-session", async (c, next) => {
  const token = await getSignedCookie(c, c.env.BETTER_AUTH_SECRET, sessionCookieName(c.env));
  if (token) await endSessionIfPastMaxAge(createDb(c.env.DB), token);
  await next();
});
for (const [method, path] of AUTH_ROUTES)
  app.on(method, path, async (c) => normalizeAuthError(await getAuth(c.env).handler(c.req.raw)));
app.all("/api/auth/*", notFound);

// Admin routes are chained after the guards so `AppType` carries their types.
const routes = app
  .use("/api/*", requireAdmin, requireSameOriginJson, rateLimitAdmin)
  .route("/api/users", users)
  .route("/api/invites", invites)
  .route("/api/overview", overview);

export type AppType = typeof routes;
export { app };
export default { fetch: app.fetch } satisfies ExportedHandler<Env>;
