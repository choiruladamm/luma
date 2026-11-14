import { Hono } from "hono";
import { getAuth } from "./auth";
import type { AppEnv } from "./env";
import { ApiError, onError } from "./errors";
import { rateLimitIp, requestId, requireAdmin, requireSameOriginJson, securityHeaders } from "./middleware";

/**
 * Endpoint Better Auth yang dibuka: cuma alur login Google redirect. Sisanya
 * (sign-up, update-user, list-sessions, dll.) 404.
 */
export const AUTH_ROUTES = [
  ["GET", "/api/auth/get-session"],
  ["POST", "/api/auth/sign-in/social"],
  ["GET", "/api/auth/callback/google"],
  ["POST", "/api/auth/sign-out"],
] as const;

const notFound = () => {
  throw new ApiError(404, "NOT_FOUND", "Not found");
};

// Urutan: requestId → rateLimit IP → [/api/auth/* → Better Auth] → sesi + admin → mutasi JSON/Origin → route.
const app = new Hono<AppEnv>().use(securityHeaders, requestId).use("/api/*", rateLimitIp);
for (const [method, path] of AUTH_ROUTES) app.on(method, path, (c) => getAuth(c.env).handler(c.req.raw));
app.all("/api/auth/*", notFound);

// Route admin di-chain setelah guard supaya `AppType` ikut membawa tipenya.
const routes = app.use("/api/*", requireAdmin, requireSameOriginJson);

app.notFound(notFound);
app.onError(onError);

export type AppType = typeof routes;
export { app };
export default { fetch: app.fetch } satisfies ExportedHandler<Env>;
