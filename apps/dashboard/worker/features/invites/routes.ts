import {
  inviteCodeParam,
  inviteCreateRequest,
  inviteListQuery,
} from "@luma/contracts/dashboard/invites";
import { factory } from "../../env";
import { audit } from "../../lib/audit";
import { validate } from "@luma/worker-kit/middleware";
import { createInvites, deleteInvite, getInvites } from "./service";

// Chained so every route's types reach `AppType` (RPC client).
export const invites = factory
  .createApp()
  .get("/", validate("query", inviteListQuery), async (c) =>
    c.json(await getInvites(c.var.db, c.req.valid("query"))),
  )
  .post("/", validate("json", inviteCreateRequest), async (c) => {
    const result = await createInvites(c.var.db, c.req.valid("json").count);
    // Count only: a logged code could be redeemed by anyone who can read Workers Logs.
    audit(c, "invite.create", `count:${result.codes.length}`);
    return c.json(result, 201);
  })
  .delete("/:code", validate("param", inviteCodeParam), async (c) => {
    const code = await deleteInvite(c.var.db, c.req.valid("param").code);
    audit(c, "invite.delete", code);
    return c.body(null, 204);
  });
