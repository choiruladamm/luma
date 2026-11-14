import { getAuth } from "./auth/auth";
import { factory } from "./env";
import { invites } from "./features/invites/routes";
import { users } from "./features/users/routes";
import { ApiError, onError } from "./lib/errors";
import { rateLimitAdmin, rateLimitIp } from "./middleware/rate-limit";
import { requestId } from "./middleware/request-id";
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

const notFound = () => {
  throw new ApiError(404, "NOT_FOUND", "Not found");
};

// Order: requestId → IP rate limit → [/api/auth/* → Better Auth] → session + admin → mutation checks → route.
const app = factory.createApp().use(securityHeaders, requestId).use("/api/*", rateLimitIp);
for (const [method, path] of AUTH_ROUTES) app.on(method, path, (c) => getAuth(c.env).handler(c.req.raw));
app.all("/api/auth/*", notFound);

// Admin routes are chained after the guards so `AppType` carries their types.
const routes = app
  .use("/api/*", requireAdmin, requireSameOriginJson, rateLimitAdmin)
  .route("/api/users", users)
  .route("/api/invites", invites);

app.notFound(notFound);
app.onError(onError);

export type AppType = typeof routes;
export { app };
export default { fetch: app.fetch } satisfies ExportedHandler<Env>;
