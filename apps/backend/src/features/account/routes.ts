import { Hono } from "hono";
import { createDb } from "../../db/client";
import type { AppEnv, SessionUser } from "../../env";
import { requireSession } from "../../middleware/session";
import { deleteAccount } from "./service";

export const account = new Hono<AppEnv>()
  .use(requireSession)
  .get("/", (c) => c.json<{ user: SessionUser }>({ user: c.get("user") }))
  .delete("/", async (c) => {
    const result = await deleteAccount(createDb(c.env.DB), c.env.BUCKET, c.get("user").id);
    return c.json(result, result.status === "deleted" ? 200 : 202);
  });
