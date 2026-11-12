import { Hono } from "hono";
import { openRouterAdmin } from "../../clients/openrouter";
import { createDb } from "../../db/client";
import type { AppEnv, SessionUser } from "../../env";
import { requireSession } from "../../middleware/session";
import { revokeKey } from "../ai-key/service";
import { deleteAccount } from "./service";

export const account = new Hono<AppEnv>()
  .use(requireSession)
  .get("/", (c) => c.json<{ user: SessionUser }>({ user: c.get("user") }))
  .delete("/", async (c) => {
    const db = createDb(c.env.DB);
    const userId = c.get("user").id;
    // Key OpenRouter dicabut duluan: walau hapus R2 masih "pending", kuota AI udah mati.
    await revokeKey(db, openRouterAdmin(c.env.OPENROUTER_MANAGEMENT_KEY), userId);
    const result = await deleteAccount(db, c.env.BUCKET, userId);
    return c.json(result, result.status === "deleted" ? 200 : 202);
  });
