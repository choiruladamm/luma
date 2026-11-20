import { Hono } from "hono";
import type { HealthResponse } from "@luma/contracts/backend/health";
import type { AppEnv } from "../../env";

/** No D1/R2: called without spending any row budget. */
export const health = new Hono<AppEnv>().get("/", (c) =>
  c.json<HealthResponse>({ status: "ok", env: c.env.ENV }),
);
