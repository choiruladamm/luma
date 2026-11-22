import { env } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { HttpResponse, http } from "msw";
import { describe, expect, it, vi } from "vitest";
import { OPENROUTER_API } from "@luma/core/openrouter";
import { createDb } from "@luma/core/db/client";
import { inviteCodes, usageDaily, userStorage, users } from "@luma/core/db/schema";
import { DAY_MS } from "@luma/core/encoding";
import { getOverview, getUsageOverview } from "../../worker/features/overview/service";
import { call } from "../helpers/app";
import { adminCookie, createUser } from "../helpers/session";
import { network } from "../setup";

const NOW = new Date("2026-11-14T15:00:00Z");
const TODAY = Math.floor(NOW.getTime() / DAY_MS);

/** Fake `GET /activity` (completed days only, like OpenRouter). Returns the request count. */
function fakeActivity(rows: { date: string; usage: number }[] | "fail") {
  const calls: string[] = [];
  network.use(
    http.get(`${OPENROUTER_API}/activity`, ({ request }) => {
      calls.push(new URL(request.url).searchParams.get("workspace_id") ?? "");
      return rows === "fail"
        ? HttpResponse.json({}, { status: 500 })
        : HttpResponse.json({ data: rows });
    }),
  );
  return calls;
}

const overview = () => getOverview(createDb(env.DB), env, "req-test", NOW);

// Runs first: the D1 of this file is still empty (no admin cookie created yet).
describe("getOverview", () => {
  it("returns zeros on an empty database", async () => {
    fakeActivity([]);
    expect(await overview()).toEqual({
      users: { total: 0, new7d: 0, banned: 0 },
      storage: { r2_bytes: 0, sync_bytes: 0 },
      sync_today: { rows: 0, limit: 100_000 },
      invites: { unused: 0 },
      flags: { sync: true, backup: true, ai_key: true },
      ai: { spend_usd: 0, budget_usd: 5, as_of: "2026-11-13" },
    });
  });

  it("counts mixed data and only today's sync rows", async () => {
    const db = createDb(env.DB);
    const old = await createUser({ createdAt: new Date(NOW.getTime() - 30 * DAY_MS) });
    const recent = await createUser({ createdAt: new Date(NOW.getTime() - 2 * DAY_MS) });
    const bannedOld = await createUser({ createdAt: new Date(NOW.getTime() - 10 * DAY_MS) });
    await db.update(users).set({ banned: true }).where(eq(users.id, bannedOld.id));
    await db.insert(userStorage).values([
      { userId: old.id, bytes: 1000, syncBytes: 10, syncDay: TODAY, syncRows: 40 },
      { userId: recent.id, bytes: 500, syncBytes: 5, syncDay: TODAY - 1, syncRows: 999 },
    ]);
    await db
      .insert(inviteCodes)
      .values([
        { code: "LUMA-OVR1" },
        { code: "LUMA-OVR2" },
        { code: "LUMA-OVR3", usedAt: NOW, usedBy: recent.id },
      ]);
    const calls = fakeActivity([
      { date: "2026-10-31 00:00:00", usage: 1 },
      { date: "2026-11-01 00:00:00", usage: 0.25 },
      { date: "2026-11-13 00:00:00", usage: 0.125 },
    ]);

    const result = await overview();
    expect(result.users).toEqual({ total: 3, new7d: 1, banned: 1 });
    expect(result.storage).toEqual({ r2_bytes: 1500, sync_bytes: 15 });
    // Yesterday's 999 rows don't count.
    expect(result.sync_today).toEqual({ rows: 40, limit: 100_000 });
    expect(result.invites).toEqual({ unused: 2 });
    // October is outside the current month.
    expect(result.ai).toEqual({ spend_usd: 0.375, budget_usd: 5, as_of: "2026-11-13" });
    expect(calls).toEqual([env.OPENROUTER_WORKSPACE_ID]);
  });

  it("keeps the overview with spend_usd: null when OpenRouter fails", async () => {
    fakeActivity("fail");
    const err = vi.spyOn(console, "error").mockImplementation(() => {});
    expect((await overview()).ai).toEqual({ spend_usd: null, budget_usd: 5, as_of: "2026-11-13" });
    expect(err).toHaveBeenCalled();
    err.mockRestore();
  });

  it("skips OpenRouter when no management key is set (local dev / e2e)", async () => {
    const calls = fakeActivity([]);
    const result = await getOverview(
      createDb(env.DB),
      { ...env, OPENROUTER_MANAGEMENT_KEY: "" },
      "r",
      NOW,
    );
    expect(result.ai.spend_usd).toBeNull();
    expect(calls).toEqual([]);
  });

  it("reads switches from the injected backend vars", async () => {
    fakeActivity([]);
    const result = await getOverview(
      createDb(env.DB),
      { ...env, SYNC_ENABLED: "false", AI_KEY_ENABLED: "nope" },
      "r",
      NOW,
    );
    expect(result.flags).toEqual({ sync: false, backup: true, ai_key: false });
  });
});

describe("GET /api/overview", () => {
  it("answers in one D1 batch (+1 guard) and one subrequest", async () => {
    const calls = fakeActivity([]);
    const { response, d1Queries } = await call("/api/overview", {
      headers: { cookie: await adminCookie() },
    });
    expect(response.status).toBe(200);
    // guard 1 + batch of 3 statements.
    expect(d1Queries).toBe(4);
    expect(calls).toHaveLength(1);
    expect(await response.json()).toMatchObject({
      sync_today: { limit: 100_000 },
      flags: { sync: true },
    });
  });
});

describe("GET /api/overview/usage", () => {
  const row = (userId: string, over: Partial<typeof usageDaily.$inferInsert>) => ({
    userId,
    day: "2026-11-14",
    feature: "group",
    model: "m1",
    bookKey: "b1",
    bookTitle: "Meditations",
    keySource: "subsidy",
    calls: 10,
    failed: 1,
    promptTokens: 100,
    completionTokens: 10,
    costUsd: 0.5,
    readingSeconds: 0,
    updatedAt: 0,
    ...over,
  });
  const reading = (userId: string, day: string, seconds: number) =>
    row(userId, {
      day,
      feature: "reading",
      model: "",
      keySource: "",
      calls: 0,
      failed: 0,
      promptTokens: 0,
      completionTokens: 0,
      costUsd: null,
      readingSeconds: seconds,
    });

  it("sums every user's rollup per day, feature, model, key, user, and book", async () => {
    const a = await createUser();
    const b = await createUser();
    await createDb(env.DB)
      .insert(usageDaily)
      .values([
        row(a.id, {}),
        row(a.id, {
          day: "2026-11-10",
          feature: "chat",
          model: "m2",
          keySource: "own",
          costUsd: null,
        }),
        reading(a.id, "2026-11-14", 600),
        row(b.id, { calls: 2, failed: 0, costUsd: 0.25 }),
        reading(b.id, "2026-11-13", 300),
        // Last month: outside the month total, inside the 30-day range.
        row(b.id, { day: "2026-10-30", calls: 1, failed: 0, costUsd: 0.125 }),
        // Outside the 30-day range.
        row(b.id, { day: "2026-10-01", calls: 99 }),
      ]);

    const usage = await getUsageOverview(createDb(env.DB), 30, NOW.getTime());

    expect(usage).toEqual({
      from: "2026-10-16",
      to: "2026-11-14",
      totals: { calls: 23, failed: 2, cost_usd: 0.875, reading_seconds: 900, active_users: 2 },
      month: { from: "2026-11-01", cost_usd: 0.75 },
      active: { day: 2, week: 2 },
      days: [
        { day: "2026-10-30", calls: 1, failed: 0, cost_usd: 0.125, active_users: 1 },
        { day: "2026-11-10", calls: 10, failed: 1, cost_usd: null, active_users: 1 },
        { day: "2026-11-13", calls: 0, failed: 0, cost_usd: null, active_users: 1 },
        { day: "2026-11-14", calls: 12, failed: 1, cost_usd: 0.75, active_users: 2 },
      ],
      features: [
        { feature: "group", calls: 13, failed: 1, cost_usd: 0.875 },
        { feature: "chat", calls: 10, failed: 1, cost_usd: null },
      ],
      models: [
        { model: "m1", calls: 13, failed: 1, cost_usd: 0.875 },
        { model: "m2", calls: 10, failed: 1, cost_usd: null },
      ],
      key_sources: [
        { key_source: "subsidy", calls: 13, failed: 1, cost_usd: 0.875 },
        { key_source: "own", calls: 10, failed: 1, cost_usd: null },
      ],
      top_users: [
        { id: a.id, email: a.email, name: "Tester", calls: 20, failed: 2, cost_usd: 0.5 },
        { id: b.id, email: b.email, name: "Tester", calls: 3, failed: 0, cost_usd: 0.375 },
      ],
      top_books: [{ book_title: "Meditations", readers: 2, reading_seconds: 900 }],
    });
  });

  it("answers in one D1 batch and rejects a bad range", async () => {
    const cookie = await adminCookie();
    const { response, d1Queries } = await call("/api/overview/usage?days=7", {
      headers: { cookie },
    });
    expect(response.status).toBe(200);
    // guard 1 + batch of 9 statements.
    expect(d1Queries).toBe(10);
    for (const days of ["0", "91", "x"]) {
      const bad = await call(`/api/overview/usage?days=${days}`, { headers: { cookie } });
      expect(bad.response.status).toBe(400);
    }
  });
});
