import { z } from "zod";

export const USERS_PAGE_SIZE = 50;

/** `:id` of the user routes. */
export const userIdParam = z.object({
  id: z.string().regex(/^[A-Za-z0-9_-]{1,64}$/, "Invalid user id"),
});

/** `GET /api/users` query. */
export const userListQuery = z.object({
  q: z.string().trim().max(100).optional(),
  status: z.enum(["active", "banned"]).optional(),
  ai: z.enum(["yes", "no"]).optional(),
  activity: z.enum(["7d", "30d", "never"]).optional(),
  sort: z.enum(["created", "lastActive", "r2", "sync", "relevance"]).optional(),
  dir: z.enum(["asc", "desc"]).default("desc"),
  page: z.coerce.number().int().min(1).max(10_000).default(1),
  limit: z.coerce.number().int().min(1).max(USERS_PAGE_SIZE).default(USERS_PAGE_SIZE),
});

export const userItem = z.strictObject({
  id: z.string(),
  email: z.string(),
  name: z.string(),
  created_at: z.string(),
  last_active_at: z.string().nullable(),
  banned: z.boolean(),
  has_ai_key: z.boolean(),
  r2_bytes: z.number(),
  sync_bytes: z.number(),
});

export const userListResponse = z.strictObject({
  items: z.array(userItem),
  total: z.number(),
  page: z.number(),
  page_count: z.number(),
});
export type UserList = z.infer<typeof userListResponse>;

export const userDetailResponse = userItem.extend({
  sessions: z.array(
    z.strictObject({
      user_agent: z.string().nullable(),
      ip_address: z.string().nullable(),
      created_at: z.string(),
      updated_at: z.string(),
    }),
  ),
  /** The subsidized key; `usage_daily` is null when OpenRouter failed. */
  ai: z
    .strictObject({
      limit: z.number(),
      usage_daily: z.number().nullable(),
      expires_at: z.string(),
    })
    .nullable(),
  invite: z.strictObject({ code: z.string(), used_at: z.string().nullable() }).nullable(),
  /** Better Auth provider ids ("google", "credential" for email/password). */
  providers: z.array(z.string()),
});
export type UserDetail = z.infer<typeof userDetailResponse>;

export const banResponse = z.strictObject({ banned: z.literal(true), key_revoked: z.boolean() });
export type BanResult = z.infer<typeof banResponse>;

export const unbanResponse = z.strictObject({ banned: z.literal(false) });
export type UnbanResult = z.infer<typeof unbanResponse>;

/** Longest range `GET /api/users/:id/usage` reads (docs/dashboard.md, API routes and errors). */
export const USAGE_MAX_DAYS = 365;

/** Books listed per user, by reading time then AI calls. */
export const USAGE_TOP_BOOKS = 20;

/** `GET /api/users/:id/usage` query: the last `days` days, today included (UTC). */
export const userUsageQuery = z.object({
  days: z.coerce.number().int().min(1).max(USAGE_MAX_DAYS).default(30),
});

const aiCounts = {
  calls: z.number(),
  failed: z.number(),
  /** Null when no call in the group reported a cost. */
  cost_usd: z.number().nullable(),
};

/** The user's `usage_daily` rollup over `from`..`to` (the app's local days). */
export const userUsageResponse = z.strictObject({
  from: z.string(),
  to: z.string(),
  totals: z.strictObject({
    ...aiCounts,
    prompt_tokens: z.number(),
    completion_tokens: z.number(),
    reading_seconds: z.number(),
    active_days: z.number(),
    /** Latest day with any row, also before `from`; null when the app never sent usage. */
    last_day: z.string().nullable(),
  }),
  /** AI rows only: `group` (Artinya), `breakdown` (Bedahin), `chat` (Ngobrolin). */
  features: z.array(
    z.strictObject({
      feature: z.string(),
      ...aiCounts,
      prompt_tokens: z.number(),
      completion_tokens: z.number(),
    }),
  ),
  models: z.array(z.strictObject({ model: z.string(), ...aiCounts })),
  /** `own` (BYOK) or `subsidy`; `""` for calls logged before the key source was recorded. */
  key_sources: z.array(z.strictObject({ key_source: z.string(), ...aiCounts })),
  books: z.array(
    z.strictObject({
      book_key: z.string(),
      book_title: z.string().nullable(),
      reading_seconds: z.number(),
      ...aiCounts,
    }),
  ),
});
export type UserUsage = z.infer<typeof userUsageResponse>;
