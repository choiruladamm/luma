// API responses shaped like the worker's (see test/integration for the server side).
export const admin = {
  user: { id: "admin-1", email: "admin@luma.test", name: "Marcus", image: null },
  session: { expires_at: "2099-01-01T00:00:00.000Z" },
};

export const overview = {
  users: { total: 48, new7d: 6, banned: 1 },
  storage: { r2_bytes: 3_200_000_000, sync_bytes: 186_000_000 },
  sync_today: { rows: 12_480, limit: 100_000 },
  invites: { unused: 9 },
  flags: { sync: true, backup: true, ai_key: false },
  ai: { spend_usd: 0.0068, budget_usd: 5, as_of: "2026-11-13" },
};

export const user = (i: number, extra: Record<string, unknown> = {}) => ({
  id: `u${i}`,
  email: `user${i}@luma.test`,
  name: `User ${i}`,
  created_at: "2026-11-10T03:00:00.000Z",
  last_active_at: null as string | null,
  banned: false,
  has_ai_key: false,
  r2_bytes: 1024 * 1024 * i,
  sync_bytes: 2048 * i,
  ...extra,
});

export const userDetail = (extra: Record<string, unknown> = {}) => ({
  ...user(1, { email: "sekar.ayu@gmail.com", name: "Sekar Ayu", has_ai_key: true }),
  sessions: [
    {
      user_agent: "Luma/0.3.0 (+mailto:x)",
      ip_address: "",
      created_at: "2026-11-10T03:00:00.000Z",
      updated_at: "2026-11-14T03:00:00.000Z",
    },
  ],
  ai: { limit: 0.02, usage_daily: 0.004, expires_at: "2026-12-14T00:00:00.000Z" },
  invite: { code: "LUMA-7KQ2", used_at: "2026-11-10T03:00:00.000Z" },
  providers: ["google"],
  ...extra,
});

export const userUsage = (extra: Record<string, unknown> = {}) => ({
  from: "2026-10-16",
  to: "2026-11-14",
  totals: {
    calls: 40,
    failed: 2,
    cost_usd: 0.0123,
    prompt_tokens: 9000,
    completion_tokens: 2000,
    reading_seconds: 5400,
    active_days: 6,
    last_day: "2026-11-13",
  },
  features: [
    {
      feature: "group",
      calls: 30,
      failed: 2,
      cost_usd: 0.01,
      prompt_tokens: 7000,
      completion_tokens: 1500,
    },
    {
      feature: "chat",
      calls: 10,
      failed: 0,
      cost_usd: null,
      prompt_tokens: 2000,
      completion_tokens: 500,
    },
  ],
  models: [{ model: "google/gemini-2.5-flash-lite", calls: 40, failed: 2, cost_usd: 0.0123 }],
  key_sources: [
    { key_source: "subsidy", calls: 30, failed: 2, cost_usd: 0.0123 },
    { key_source: "own", calls: 10, failed: 0, cost_usd: null },
  ],
  books: [
    {
      book_key: "b1",
      book_title: "Meditations",
      reading_seconds: 5400,
      calls: 38,
      failed: 2,
      cost_usd: 0.0123,
    },
    { book_key: "", book_title: null, reading_seconds: 0, calls: 2, failed: 0, cost_usd: null },
  ],
  ...extra,
});

export const invites = {
  items: [
    {
      code: "LUMA-AAAAA-BBBBB",
      created_at: "2026-11-14T03:00:00.000Z" as string | null,
      used_by: null,
      used_at: null,
    },
    // Made before created_at was recorded.
    { code: "LUMA-CCCCC-DDDDD", created_at: null, used_by: null, used_at: null },
    {
      code: "LUMA-EEEEE-FFFFF",
      created_at: "2026-11-01T03:00:00.000Z",
      used_by: { id: "u1", email: "user1@luma.test" },
      used_at: "2026-11-12T03:00:00.000Z",
    },
  ],
};

/** A `GET /api/users` page: `{items, total, page, page_count}` (50 per page unless told). */
export const usersPage = (
  items: ReturnType<typeof user>[],
  { total = items.length, page = 1, limit = 50 } = {},
) => ({
  items,
  total,
  page,
  page_count: Math.max(1, Math.ceil(total / limit)),
});

type InviteRow = (typeof invites.items)[number];

/**
 * A `GET /api/invites` answer for `items`, applying the query like the worker would (status,
 * used-within skipped, q on code/email, code sort, page/limit), with counts that follow `q`.
 */
export function invitesPage(items: InviteRow[], url: URL) {
  const p = url.searchParams;
  const q = (p.get("q") ?? "").toLowerCase().replaceAll("-", "");
  const searched = items.filter(
    (i) =>
      !q ||
      i.code.toLowerCase().replaceAll("-", "").includes(q) ||
      (i.used_by?.email.toLowerCase().includes(q) ?? false),
  );
  const status = p.get("status");
  let rows = searched.filter((i) => !status || (status === "used") === (i.used_at !== null));
  if (p.get("sort") === "code")
    rows = rows.toSorted(
      (a, b) => (p.get("dir") === "asc" ? 1 : -1) * a.code.localeCompare(b.code),
    );
  const limit = Number(p.get("limit") ?? 20);
  const page = Number(p.get("page") ?? 1);
  return {
    items: rows.slice((page - 1) * limit, page * limit),
    total: rows.length,
    page,
    page_count: Math.max(1, Math.ceil(rows.length / limit)),
    counts: {
      all: searched.length,
      unused: searched.filter((i) => !i.used_at).length,
      used: searched.filter((i) => i.used_at).length,
    },
  };
}
