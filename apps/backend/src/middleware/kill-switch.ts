import { createMiddleware } from "hono/factory";
import type { AppEnv, FeatureFlag } from "../env";
import { ApiError } from "../lib/errors";

/** Retry-After when a feature is off: the client stops until the next trigger after this delay. */
export const DISABLED_RETRY_AFTER_SECONDS = 3600;

/** Kill switch: `false` → 503 before D1/R2 is touched. Only "true" counts as on. */
export const killSwitch = (flag: FeatureFlag) =>
  createMiddleware<AppEnv>(async (c, next) => {
    if (c.env[flag] !== "true") {
      throw new ApiError(503, "SERVICE_DISABLED", `${flag} is off`, {
        "Retry-After": String(DISABLED_RETRY_AFTER_SECONDS),
      });
    }
    await next();
  });
