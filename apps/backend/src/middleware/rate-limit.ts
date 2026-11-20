import type { Context } from "hono";
import { rateLimit as limitBy } from "@luma/worker-kit/middleware";
import type { AppEnv } from "../env";
import { RATE_LIMIT_PERIOD_SECONDS } from "./policy";

export const clientIp = (c: Context) => c.req.header("cf-connecting-ip") ?? "unknown";

/** The RATE_LIMITER binding per key: IP on all `/v1/*`, user on quota-bearing features. */
export const rateLimit = (key: (c: Context<AppEnv>) => string) =>
  limitBy<AppEnv>({
    limiter: (c) => c.env.RATE_LIMITER,
    key,
    periodSeconds: RATE_LIMIT_PERIOD_SECONDS,
  });
