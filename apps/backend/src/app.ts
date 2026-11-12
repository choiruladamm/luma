import { Hono } from "hono";
import type { AppEnv } from "./env";
import { account } from "./features/account/routes";
import { auth } from "./features/auth/routes";
import { health } from "./features/health/routes";
import { legal } from "./features/legal/routes";
import { ApiError, onError } from "./lib/errors";
import { clientIp, rateLimit } from "./middleware/rate-limit";
import { requestId } from "./middleware/request-id";

// Urutan middleware: requestId → killSwitch → bodyLimit → session → rateLimit → validator
// (docs/backend.md, Arsitektur kode). killSwitch/bodyLimit/session dipasang per grup route.
export const app = new Hono<AppEnv>();

app.use(requestId);
app.use("/v1/*", rateLimit(clientIp));
app.route("/v1/health", health);
app.route("/v1/auth", auth);
app.route("/v1/me", account);
app.route("/", legal);

app.notFound(() => {
  throw new ApiError(404, "NOT_FOUND", "Not found");
});
app.onError(onError);
