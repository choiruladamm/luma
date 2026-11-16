import { factory } from "../env";

/** Every response, including errors and Better Auth responses. */
export const securityHeaders = factory.createMiddleware(async (c, next) => {
  await next();
  c.res.headers.set("Content-Security-Policy", "default-src 'self'; frame-ancestors 'none'");
  c.res.headers.set("X-Content-Type-Options", "nosniff");
});
