import { Hono } from "hono";
import type { AppEnv } from "../../env";

export type HealthResponse = { status: "ok"; env: string };

/** Tanpa D1/R2: dipanggil tanpa makan anggaran baris. */
export const health = new Hono<AppEnv>().get("/", (c) =>
  c.json<HealthResponse>({ status: "ok", env: c.env.ENV }),
);
