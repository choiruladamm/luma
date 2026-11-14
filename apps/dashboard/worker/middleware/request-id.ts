import { factory } from "../env";

export const requestId = factory.createMiddleware(async (c, next) => {
  const id = crypto.randomUUID();
  c.set("requestId", id);
  c.header("x-request-id", id);
  await next();
});
