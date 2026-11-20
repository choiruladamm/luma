import { rateLimit } from "@luma/worker-kit/middleware";
import type { AppEnv } from "../env";
import { isMutation } from "./same-origin";

/** Period of both rate-limit bindings (wrangler.jsonc). */
const PERIOD_SECONDS = 60;

/** RATE_LIMITER binding per IP, before auth and D1. */
export const rateLimitIp = rateLimit<AppEnv>({
  limiter: (c) => c.env.RATE_LIMITER,
  key: (c) => `ip:${c.req.header("cf-connecting-ip") ?? "unknown"}`,
  periodSeconds: PERIOD_SECONDS,
});

/** Misclicks / runaway scripts: mutations are limited per admin (ADMIN_RATE_LIMITER binding, 30/min). Reads are not. */
export const rateLimitAdmin = rateLimit<AppEnv>({
  limiter: (c) => c.env.ADMIN_RATE_LIMITER,
  key: (c) => (isMutation(c.req.method) ? `admin:${c.var.admin.id}` : null),
  periodSeconds: PERIOD_SECONDS,
});
