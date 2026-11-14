import { factory } from "../env";
import { ApiError } from "../lib/errors";
import { isMutation } from "./same-origin";

export const RATE_LIMIT_PERIOD_SECONDS = 60;

const tooMany = () =>
  new ApiError(429, "RATE_LIMITED", "Too many requests", { "Retry-After": String(RATE_LIMIT_PERIOD_SECONDS) });

/** RATE_LIMITER binding per IP, before auth and D1. */
export const rateLimitIp = factory.createMiddleware(async (c, next) => {
  const ip = c.req.header("cf-connecting-ip") ?? "unknown";
  if (!(await c.env.RATE_LIMITER.limit({ key: `ip:${ip}` })).success) throw tooMany();
  await next();
});

/** Misclicks / runaway scripts: mutations are limited per admin (ADMIN_RATE_LIMITER binding, 30/min). Reads are not. */
export const rateLimitAdmin = factory.createMiddleware(async (c, next) => {
  if (isMutation(c.req.method) && !(await c.env.ADMIN_RATE_LIMITER.limit({ key: `admin:${c.var.admin.id}` })).success) {
    throw tooMany();
  }
  await next();
});
