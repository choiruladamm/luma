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

// Middleware order: requestId → killSwitch → bodyLimit → session → rateLimit → validator
// (docs/backend.md, Request pipeline and API conventions). killSwitch/bodyLimit/session are mounted per route group.
export const app = workerApp(new Hono<AppEnv>());

app.use("/v1/*", rateLimit(clientIp), deps);
app.route("/v1/health", health);
app.route("/v1/auth", auth);
app.route("/v1/me", account);
app.route("/v1/ai", ai);
app.route("/v1/files", files);
app.route("/v1/backups", backups);
app.route("/v1/sync", sync);
app.route("/", legal);
