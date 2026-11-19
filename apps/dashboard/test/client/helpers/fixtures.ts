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
