import { z } from "zod";

export const overviewResponse = z.strictObject({
  users: z.strictObject({ total: z.number(), new7d: z.number(), banned: z.number() }),
  storage: z.strictObject({ r2_bytes: z.number(), sync_bytes: z.number() }),
  sync_today: z.strictObject({ rows: z.number(), limit: z.number() }),
  invites: z.strictObject({ unused: z.number() }),
  flags: z.strictObject({ sync: z.boolean(), backup: z.boolean(), ai_key: z.boolean() }),
  /** `spend_usd` is null when OpenRouter is unreachable or unconfigured; `as_of` is a UTC day. */
  ai: z.strictObject({
    spend_usd: z.number().nullable(),
    budget_usd: z.number(),
    as_of: z.string(),
  }),
});
export type Overview = z.infer<typeof overviewResponse>;
