import { z } from "zod";

export const overviewResponse = z.strictObject({
  users: z.strictObject({ total: z.number(), new7d: z.number(), banned: z.number() }),
  storage: z.strictObject({ r2Bytes: z.number(), syncBytes: z.number() }),
  syncToday: z.strictObject({ rows: z.number(), limit: z.number() }),
  invites: z.strictObject({ unused: z.number() }),
  flags: z.strictObject({ sync: z.boolean(), backup: z.boolean(), aiKey: z.boolean() }),
  /** `spendUsd` is null when OpenRouter is unreachable or unconfigured; `asOf` is a UTC day. */
  ai: z.strictObject({ spendUsd: z.number().nullable(), budgetUsd: z.number(), asOf: z.string() }),
});
export type Overview = z.infer<typeof overviewResponse>;
