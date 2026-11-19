import { z } from "zod";
import { factory } from "../../env";
import { audit } from "../../lib/audit";
import { validate } from "@luma/worker-kit/middleware";
import { createInvites, deleteInvite, getInvites, INVITES_PAGE_SIZE } from "./service";

export const MAX_INVITES_PER_REQUEST = 20;

const listQuery = z.object({
  status: z.enum(["unused", "used"]).optional(),
  usedWithin: z.enum(["7d", "30d"]).optional(),
  q: z.string().trim().max(100).optional(),
  sort: z.enum(["default", "usedAt", "createdAt", "code"]).default("default"),
  dir: z.enum(["asc", "desc"]).default("desc"),
  page: z.coerce.number().int().min(1).max(10_000).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(INVITES_PAGE_SIZE),
});
const createBody = z
  .object({ count: z.number().int().min(1).max(MAX_INVITES_PER_REQUEST) })
  .strict();
const codeParam = z.object({
  code: z.string().regex(/^[A-Za-z0-9-]{4,32}$/, "Invalid invite code"),
});

// Chained so every route's types reach `AppType` (RPC client).
export const invites = factory
  .createApp()
  .get("/", validate("query", listQuery), async (c) =>
    c.json(await getInvites(c.var.db, c.req.valid("query"))),
  )
  .post("/", validate("json", createBody), async (c) => {
    const result = await createInvites(c.var.db, c.req.valid("json").count);
    // Count only: a logged code could be redeemed by anyone who can read Workers Logs.
    audit(c, "invite.create", `count:${result.codes.length}`);
    return c.json(result, 201);
  })
  .delete("/:code", validate("param", codeParam), async (c) => {
    const code = await deleteInvite(c.var.db, c.req.valid("param").code);
    audit(c, "invite.delete", code);
    return c.body(null, 204);
  });
