import { killSwitch } from "@luma/worker-kit/middleware";
import type { FeatureFlag } from "../env";
import { DISABLED_RETRY_AFTER_SECONDS } from "./policy";
import { rateLimit } from "./rate-limit";
import { requireSession } from "./session";

/**
 * Pipeline for quota-bearing features (docs/backend.md, Request pipeline and API conventions): kill
 * switch → session → per-user rate limit. The switch goes first, so a disabled feature never touches D1.
 */
export const featureGuard = (flag: FeatureFlag) =>
  [
    killSwitch(flag, DISABLED_RETRY_AFTER_SECONDS),
    requireSession,
    rateLimit((c) => `user:${c.get("user").id}`),
  ] as const;
