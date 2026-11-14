import { z } from "zod";
import { openRouterAdmin } from "../../../../backend/src/clients/openrouter";
import { factory } from "../../env";
import { audit } from "../../lib/audit";
import { validate } from "../../middleware/validate";
import { ban, getUserDetail, getUsers, unban, USERS_PAGE_SIZE } from "./service";

const userId = z.object({ id: z.string().regex(/^[A-Za-z0-9_-]{1,64}$/, "Invalid user id") });

const listQuery = z.object({
  q: z.string().trim().max(100).optional(),
  cursor: z
    .string()
    .regex(/^\d{1,15},[A-Za-z0-9_-]{1,64}$/, "Invalid cursor")
    .transform((v) => {
      const [ms, id] = v.split(",") as [string, string];
      return { createdAt: new Date(Number(ms)), id };
    })
    .optional(),
  limit: z.coerce.number().int().min(1).max(USERS_PAGE_SIZE).default(USERS_PAGE_SIZE),
});

// Chained so every route's types reach `AppType` (RPC client).
export const users = factory
  .createApp()
  .get("/", validate("query", listQuery), async (c) => c.json(await getUsers(c.var.db, c.req.valid("query"))))
  .get("/:id", validate("param", userId), async (c) => {
    const openrouter = openRouterAdmin(c.env.OPENROUTER_MANAGEMENT_KEY);
    return c.json(await getUserDetail(c.var.db, openrouter, c.req.valid("param").id, c.var.requestId));
  })
  .post("/:id/ban", validate("param", userId), async (c) => {
    const { id } = c.req.valid("param");
    const result = await ban(c.var.db, openRouterAdmin(c.env.OPENROUTER_MANAGEMENT_KEY), id);
    audit(c, "user.ban", id);
    return c.json(result);
  })
  .post("/:id/unban", validate("param", userId), async (c) => {
    const { id } = c.req.valid("param");
    const result = await unban(c.var.db, id);
    audit(c, "user.unban", id);
    return c.json(result);
  });
