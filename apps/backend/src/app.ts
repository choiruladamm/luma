import { Hono } from "hono";
import { workerApp } from "@luma/worker-kit/app";
import type { AppEnv } from "./env";
import { account } from "./features/account/routes";
import { ai } from "./features/ai-key/routes";
import { auth } from "./features/auth/routes";
import { backups } from "./features/backup/routes";
import { files } from "./features/files/routes";
import { health } from "./features/health/routes";
import { legal } from "./features/legal/routes";
import { sync } from "./features/sync/routes";
import { deps } from "./middleware/deps";
import { clientIp, rateLimit } from "./middleware/rate-limit";
import { v1Adapter, wire } from "./middleware/v1-adapter";

// Middleware order: requestId → killSwitch → bodyLimit → session → rateLimit → validator
// (docs/backend.md, Request pipeline and API conventions). killSwitch/bodyLimit/session are mounted per route group.
export const app = workerApp(new Hono<AppEnv>());

// Both versions mount the same routers in the same order; `/v1` goes through the case adapter.
app.use("/v1/*", wire("v1"), rateLimit(clientIp), deps, v1Adapter);
app.use("/v2/*", wire("v2"), rateLimit(clientIp), deps);
for (const prefix of ["/v1", "/v2"]) {
  app.route(`${prefix}/health`, health);
  app.route(`${prefix}/auth`, auth);
  app.route(`${prefix}/me`, account);
  app.route(`${prefix}/ai`, ai);
  app.route(`${prefix}/files`, files);
  app.route(`${prefix}/backups`, backups);
  app.route(`${prefix}/sync`, sync);
}
app.route("/", legal);
