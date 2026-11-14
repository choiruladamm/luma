import type { Context } from "hono";
import type { AppEnv } from "./env";

/** Jejak mutasi admin ke Workers Logs (tanpa tabel D1): siapa, aksi apa, ke target mana. */
export function audit(c: Context<AppEnv>, action: string, targetId: string) {
  console.log(
    JSON.stringify({ message: "audit", admin: c.var.admin.email, action, targetId, requestId: c.var.requestId }),
  );
}
