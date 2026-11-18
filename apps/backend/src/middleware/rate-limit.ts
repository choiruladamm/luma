import type { Context } from "hono";
import { createMiddleware } from "hono/factory";
import type { AppEnv } from "../env";
import { ApiError } from "../lib/errors";

/** Period of the RATE_LIMITER binding (wrangler.jsonc). */
export const RATE_LIMIT_PERIOD_SECONDS = 60;

export const clientIp = (c: Context) => c.req.header("cf-connecting-ip") ?? "unknown";

/** Workers Rate Limiting per key (IP on all `/v1/*`, user on quota-bearing features). Over the limit → 429 + Retry-After. */
export const rateLimit = (key: (c: Context<AppEnv>) => string) =>
  createMiddleware<AppEnv>(async (c, next) => {
    const { success } = await c.env.RATE_LIMITER.limit({ key: key(c) });
    if (!success) {
      throw new ApiError(429, "RATE_LIMITED", "Too many requests", {
        "Retry-After": String(RATE_LIMIT_PERIOD_SECONDS),
      });
    }
    await next();
  });
