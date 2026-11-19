import { zValidator } from "@hono/zod-validator";
import type { Context, Env, ValidationTargets } from "hono";
import { bodyLimit } from "hono/body-limit";
import { createMiddleware } from "hono/factory";
import type { ZodType } from "zod";
import { ApiError } from "./errors";

/** Variables the kit's middleware and `onError` read from every request. */
export type KitEnv = { Variables: { requestId: string } };

/**
 * Assigns `x-request-id` and `c.var.requestId`. Set before the handler for responses Hono builds,
 * including errors that skip the code after `next()`, and again after it for responses built
 * outside Hono (Better Auth).
 */
export const requestId = createMiddleware<KitEnv>(async (c, next) => {
  const id = crypto.randomUUID();
  c.set("requestId", id);
  c.header("x-request-id", id);
  await next();
  c.res.headers.set("x-request-id", id);
});

/**
 * Workers Rate Limiting on `key(c)`; a null key skips the check. Over the limit → 429
 * `RATE_LIMITED` with `Retry-After` set to the binding's period.
 */
export const rateLimit = <E extends Env>(options: {
  limiter: (c: Context<E>) => RateLimit;
  key: (c: Context<E>) => string | null;
  /** The binding's `period` in wrangler.jsonc. */
  periodSeconds: number;
}) =>
  createMiddleware<E>(async (c, next) => {
    const k = options.key(c);
    if (k !== null && !(await options.limiter(c).limit({ key: k })).success) {
      throw new ApiError(429, "RATE_LIMITED", "Too many requests", {
        "Retry-After": String(options.periodSeconds),
      });
    }
    await next();
  });

/** Rejects a body over `maxSize` bytes with 413 before `JSON.parse`, so it burns no CPU. */
export const limitBody = (maxSize: number) =>
  bodyLimit({
    maxSize,
    onError: () => {
      throw new ApiError(413, "PAYLOAD_TOO_LARGE", `Body exceeds ${maxSize} bytes`);
    },
  });

/**
 * Kill switch: unless the var is the string "true" → 503 `SERVICE_DISABLED` before D1/R2 is
 * touched, with `Retry-After` telling clients when to try again.
 */
export const killSwitch = <F extends string>(flag: F, retryAfterSeconds: number) =>
  createMiddleware<{ Bindings: Record<F, string> }>(async (c, next) => {
    if (c.env[flag] !== "true") {
      throw new ApiError(503, "SERVICE_DISABLED", `${flag} is off`, {
        "Retry-After": String(retryAfterSeconds),
      });
    }
    await next();
  });

/**
 * zod validation for one request part. Failure → 400 `BAD_REQUEST` with `message`, or the first
 * zod issue when the route gives none.
 */
export const validate = <T extends keyof ValidationTargets, S extends ZodType>(
  target: T,
  schema: S,
  message?: string,
) =>
  zValidator(target, schema, (result) => {
    if (!result.success) {
      // A failed zod parse always reports at least one issue.
      /* istanbul ignore next */
      const first = result.error.issues[0]?.message ?? "Invalid input";
      throw new ApiError(400, "BAD_REQUEST", message ?? first);
    }
  });
