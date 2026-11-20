import type { Context } from "hono";
import { log } from "@luma/worker-kit/log";
import type { AppEnv } from "../env";

/** Admin mutation trail in Workers Logs (no D1 table): who, which action, which target. */
export function audit(c: Context<AppEnv>, action: string, targetId: string) {
  log.info("audit", {
    admin: c.var.admin.email,
    action,
    target_id: targetId,
    request_id: c.var.requestId,
  });
}
