import { Hono } from "hono";
import type { AppEnv, SessionUser } from "../../env";
import { requireSession } from "../../middleware/session";
import { revokeKey } from "../ai-key/service";
import { deleteAccount } from "./service";

export const account = new Hono<AppEnv>()
  .use(requireSession)
  .get("/", (c) => c.json<{ user: SessionUser }>({ user: c.get("user") }))
  .delete("/", async (c) => {
    const userId = c.get("user").id;
    // The OpenRouter key is revoked first: even if R2 deletion is still "pending", the AI quota is already dead.
    await revokeKey(c.var.db, c.var.openrouter, userId);
    const result = await deleteAccount(c.var.db, c.env.BUCKET, userId);
    return c.json(result, result.status === "deleted" ? 200 : 202);
  });
