import { z } from "zod";
import { factory } from "../../env";
import { audit } from "../../lib/audit";
import { validate } from "../../middleware/validate";
import { createInvites, deleteInvite, getInvites } from "./service";

export const MAX_INVITES_PER_REQUEST = 20;

const listQuery = z.object({ status: z.enum(["unused", "used"]).optional() });
const createBody = z.object({ count: z.number().int().min(1).max(MAX_INVITES_PER_REQUEST) }).strict();
const codeParam = z.object({ code: z.string().regex(/^[A-Za-z0-9-]{4,32}$/, "Invalid invite code") });

// Chained so every route's types reach `AppType` (RPC client).
export const invites = factory
  .createApp()
  .get("/", validate("query", listQuery), async (c) => c.json(await getInvites(c.var.db, c.req.valid("query").status)))
  .post("/", validate("json", createBody), async (c) => {
    const result = await createInvites(c.var.db, c.req.valid("json").count);
    audit(c, "invite.create", result.codes.join(","));
    return c.json(result, 201);
  })
  .delete("/:code", validate("param", codeParam), async (c) => {
    const code = await deleteInvite(c.var.db, c.req.valid("param").code);
    audit(c, "invite.delete", code);
    return c.body(null, 204);
  });
