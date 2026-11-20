import { factory } from "../env";

const HEADERS = {
  "Content-Security-Policy": "default-src 'self'; frame-ancestors 'none'",
  "X-Content-Type-Options": "nosniff",
};

/**
 * Every response, including errors and Better Auth responses. Set before the handler for
 * responses Hono builds (an error skips the code after `next()`), and again after it for
 * responses built outside Hono.
 */
export const securityHeaders = factory.createMiddleware(async (c, next) => {
  for (const [k, v] of Object.entries(HEADERS)) c.header(k, v);
  await next();
  for (const [k, v] of Object.entries(HEADERS)) c.res.headers.set(k, v);
});
