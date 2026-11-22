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

/** Longest range `GET /api/overview/usage` reads (docs/dashboard.md, API routes and errors). */
export const OVERVIEW_USAGE_MAX_DAYS = 90;

/** Rows in the top users and top books lists. */
export const OVERVIEW_TOP = 10;

/** `GET /api/overview/usage` query: the last `days` days, today included (UTC). */
export const overviewUsageQuery = z.object({
  days: z.coerce.number().int().min(1).max(OVERVIEW_USAGE_MAX_DAYS).default(30),
});

const counts = {
  calls: z.number(),
  failed: z.number(),
  /** Null when no call in the group reported a cost. */
  cost_usd: z.number().nullable(),
};

/** Cross-user `usage_daily` rollup over `from`..`to` (the apps' local days). */
export const overviewUsageResponse = z.strictObject({
  from: z.string(),
  to: z.string(),
  totals: z.strictObject({
    ...counts,
    reading_seconds: z.number(),
    /** Users with any row in the range. */
    active_users: z.number(),
  }),
  /** Reported cost since the 1st of the current UTC month, to set beside OpenRouter's spend. */
  month: z.strictObject({ from: z.string(), cost_usd: z.number().nullable() }),
  /** Daily and weekly active users: any row today, or in the last 7 days. */
  active: z.strictObject({ day: z.number(), week: z.number() }),
  /** One entry per day that has rows, oldest first. */
  days: z.array(z.strictObject({ day: z.string(), ...counts, active_users: z.number() })),
  features: z.array(z.strictObject({ feature: z.string(), ...counts })),
  models: z.array(z.strictObject({ model: z.string(), ...counts })),
  key_sources: z.array(z.strictObject({ key_source: z.string(), ...counts })),
  top_users: z.array(
    z.strictObject({ id: z.string(), email: z.string(), name: z.string(), ...counts }),
  ),
  top_books: z.array(
    z.strictObject({
      book_title: z.string().nullable(),
      readers: z.number(),
      reading_seconds: z.number(),
    }),
  ),
});
export type OverviewUsage = z.infer<typeof overviewUsageResponse>;
