import { Hono } from "hono";
import type { AppEnv } from "../../env";

export type HealthResponse = { status: "ok"; env: string };

/** No D1/R2: called without spending any row budget. */
export const health = new Hono<AppEnv>().get("/", (c) =>
  c.json<HealthResponse>({ status: "ok", env: c.env.ENV }),
);
