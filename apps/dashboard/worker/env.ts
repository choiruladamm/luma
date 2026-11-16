import { createFactory } from "hono/factory";
import type { Db } from "../../backend/src/db/client";

export type Admin = { id: string; email: string };

export type AppEnv = {
  Bindings: Env;
  /** `db` and `admin` are set by the `requireAdmin` middleware. */
  Variables: { requestId: string; db: Db; admin: Admin };
};

/** App, middleware, and feature routes are built from here so `AppEnv` is written once. */
export const factory = createFactory<AppEnv>();
