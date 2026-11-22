import { userIdParam, userListQuery, userUsageQuery } from "@luma/contracts/dashboard/users";
import { openRouterAdmin } from "@luma/core/openrouter";
import { factory } from "../../env";
import { audit } from "../../lib/audit";
import { validate } from "@luma/worker-kit/middleware";
import { ban, getUserDetail, getUserUsage, getUsers, unban } from "./service";

// Chained so every route's types reach `AppType` (RPC client).
export const users = factory
  .createApp()
  .get("/", validate("query", userListQuery), async (c) =>
    c.json(await getUsers(c.var.db, c.req.valid("query"))),
  )
  .get("/:id", validate("param", userIdParam), async (c) => {
    const openrouter = openRouterAdmin(c.env.OPENROUTER_MANAGEMENT_KEY);
    return c.json(
      await getUserDetail(c.var.db, openrouter, c.req.valid("param").id, c.var.requestId),
    );
  })
  .get("/:id/usage", validate("param", userIdParam), validate("query", userUsageQuery), async (c) =>
    c.json(await getUserUsage(c.var.db, c.req.valid("param").id, c.req.valid("query").days)),
  )
  .post("/:id/ban", validate("param", userIdParam), async (c) => {
    const { id } = c.req.valid("param");
    const result = await ban(c.var.db, openRouterAdmin(c.env.OPENROUTER_MANAGEMENT_KEY), id);
    audit(c, "user.ban", id);
    return c.json(result);
  })
  .post("/:id/unban", validate("param", userIdParam), async (c) => {
    const { id } = c.req.valid("param");
    const result = await unban(c.var.db, id);
    audit(c, "user.unban", id);
    return c.json(result);
  });
