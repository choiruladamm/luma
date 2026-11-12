import { createMiddleware } from "hono/factory";
import type { AppEnv, FeatureFlag } from "../env";
import { ApiError } from "../lib/errors";

/** Retry-After saat fitur dimatikan: client berhenti sampai pemicu berikutnya setelah jeda ini. */
export const DISABLED_RETRY_AFTER_SECONDS = 3600;

/** Saklar darurat: `false` → 503 sebelum D1/R2 disentuh. Hanya "true" yang dianggap nyala. */
export const killSwitch = (flag: FeatureFlag) =>
  createMiddleware<AppEnv>(async (c, next) => {
    if (c.env[flag] !== "true") {
      throw new ApiError(503, "SERVICE_DISABLED", `${flag} is off`, {
        "Retry-After": String(DISABLED_RETRY_AFTER_SECONDS),
      });
    }
    await next();
  });
