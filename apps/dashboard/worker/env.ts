import type { Db } from "../../backend/src/db/client";

export type Admin = { id: string; email: string };

export type AppEnv = {
  Bindings: Env;
  /** `db` dari middleware `deps`, `admin` dari `requireAdmin`. */
  Variables: { requestId: string; db: Db; admin: Admin };
};
