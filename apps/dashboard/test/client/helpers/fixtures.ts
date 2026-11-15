// API responses shaped like the worker's (see test/integration for the server side).
export const admin = { user: { id: "admin-1", email: "admin@luma.test", name: "Marcus", image: null }, session: { expiresAt: "2099-01-01T00:00:00.000Z" } };

export const overview = {
  users: { total: 48, new7d: 6, banned: 1 },
  storage: { r2Bytes: 3_200_000_000, syncBytes: 186_000_000 },
  syncToday: { rows: 12_480, limit: 100_000 },
  invites: { unused: 9 },
  flags: { sync: true, backup: true, aiKey: false },
  ai: { spendUsd: 0.0068, budgetUsd: 5, asOf: "2026-11-13" },
};

export const user = (i: number, extra: Record<string, unknown> = {}) => ({
  id: `u${i}`,
  email: `user${i}@luma.test`,
  name: `User ${i}`,
  createdAt: "2026-11-10T03:00:00.000Z",
  lastActiveAt: null as string | null,
  banned: false,
  hasAiKey: false,
  r2Bytes: 1024 * 1024 * i,
  syncBytes: 2048 * i,
  ...extra,
});

export const userDetail = (extra: Record<string, unknown> = {}) => ({
  ...user(1, { email: "sekar.ayu@gmail.com", name: "Sekar Ayu", hasAiKey: true }),
  sessions: [{ userAgent: "Luma/0.3.0 (+mailto:x)", ipAddress: "", createdAt: "2026-11-10T03:00:00.000Z", updatedAt: "2026-11-14T03:00:00.000Z" }],
  ai: { limit: 0.02, usageDaily: 0.004, expiresAt: "2026-12-14T00:00:00.000Z" },
  invite: { code: "LUMA-7KQ2", usedAt: "2026-11-10T03:00:00.000Z" },
  providers: ["google"],
  ...extra,
});

export const invites = {
  items: [
    { code: "LUMA-AAAAA-BBBBB", usedBy: null, usedAt: null },
    { code: "LUMA-CCCCC-DDDDD", usedBy: null, usedAt: null },
    { code: "LUMA-EEEEE-FFFFF", usedBy: { id: "u1", email: "user1@luma.test" }, usedAt: "2026-11-12T03:00:00.000Z" },
  ],
};

/** A `GET /api/users` page: `{items, total, page, pageCount}` (50 per page unless told). */
export const usersPage = (items: ReturnType<typeof user>[], { total = items.length, page = 1, limit = 50 } = {}) => ({
  items,
  total,
  page,
  pageCount: Math.max(1, Math.ceil(total / limit)),
});
