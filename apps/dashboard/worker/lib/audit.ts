import type { Context } from "hono";
import type { AppEnv } from "../env";

/** Admin mutation trail in Workers Logs (no D1 table): who, which action, which target. */
export function audit(c: Context<AppEnv>, action: string, targetId: string) {
  console.log(
    JSON.stringify({ message: "audit", admin: c.var.admin.email, action, targetId, requestId: c.var.requestId }),
  );
}
