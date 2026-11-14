import { factory } from "../env";
import { ApiError } from "../lib/errors";

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

export const isMutation = (method: string) => !SAFE_METHODS.has(method);

/** CSRF: mutations must be JSON with `Origin` exactly the dashboard domain (403 otherwise). */
export const requireSameOriginJson = factory.createMiddleware(async (c, next) => {
  if (isMutation(c.req.method)) {
    const json = c.req.header("content-type")?.split(";")[0]?.trim().toLowerCase() === "application/json";
    const origin = c.req.header("origin") === new URL(c.env.BETTER_AUTH_URL).origin;
    if (!json || !origin) throw new ApiError(403, "FORBIDDEN", "Mutations need JSON from the dashboard origin");
  }
  await next();
});
