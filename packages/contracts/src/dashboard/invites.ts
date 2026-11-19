import { z } from "zod";

export const INVITES_PAGE_SIZE = 20;

export const MAX_INVITES_PER_REQUEST = 20;

/** `GET /api/invites` query. */
export const inviteListQuery = z.object({
  status: z.enum(["unused", "used"]).optional(),
  usedWithin: z.enum(["7d", "30d"]).optional(),
  q: z.string().trim().max(100).optional(),
  sort: z.enum(["default", "usedAt", "createdAt", "code"]).default("default"),
  dir: z.enum(["asc", "desc"]).default("desc"),
  page: z.coerce.number().int().min(1).max(10_000).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(INVITES_PAGE_SIZE),
});

/** `POST /api/invites` body. */
export const inviteCreateRequest = z.strictObject({
  count: z.number().int().min(1).max(MAX_INVITES_PER_REQUEST),
});

/** `:code` of `DELETE /api/invites/:code`. */
export const inviteCodeParam = z.object({
  code: z.string().regex(/^[A-Za-z0-9-]{4,32}$/, "Invalid invite code"),
});

export const inviteListResponse = z.strictObject({
  items: z.array(
    z.strictObject({
      code: z.string(),
      createdAt: z.string().nullable(),
      usedBy: z.strictObject({ id: z.string(), email: z.string() }).nullable(),
      usedAt: z.string().nullable(),
    }),
  ),
  total: z.number(),
  page: z.number(),
  pageCount: z.number(),
  counts: z.strictObject({ all: z.number(), unused: z.number(), used: z.number() }),
});
export type InviteList = z.infer<typeof inviteListResponse>;

export const inviteCreateResponse = z.strictObject({
  codes: z.array(z.string()),
  createdAt: z.string(),
});
export type InviteCreated = z.infer<typeof inviteCreateResponse>;
