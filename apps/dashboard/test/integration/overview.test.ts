import { env } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { HttpResponse, http } from "msw";
import { describe, expect, it, vi } from "vitest";
import { OPENROUTER_API } from "../../../backend/src/clients/openrouter";
import { createDb } from "../../../backend/src/db/client";
import { inviteCodes, userStorage, users } from "../../../backend/src/db/schema";
import { DAY_MS } from "../../../backend/src/lib/encoding";
import { getOverview } from "../../worker/features/overview/service";
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
      return rows === "fail" ? HttpResponse.json({}, { status: 500 }) : HttpResponse.json({ data: rows });
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
      storage: { r2Bytes: 0, syncBytes: 0 },
      syncToday: { rows: 0, limit: 100_000 },
      invites: { unused: 0 },
      flags: { sync: true, backup: true, aiKey: true },
      ai: { spendUsd: 0, budgetUsd: 5, asOf: "2026-11-13" },
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
    await db.insert(inviteCodes).values([
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
    expect(result.storage).toEqual({ r2Bytes: 1500, syncBytes: 15 });
    // Yesterday's 999 rows don't count.
    expect(result.syncToday).toEqual({ rows: 40, limit: 100_000 });
    expect(result.invites).toEqual({ unused: 2 });
    // October is outside the current month.
    expect(result.ai).toEqual({ spendUsd: 0.375, budgetUsd: 5, asOf: "2026-11-13" });
    expect(calls).toEqual([env.OPENROUTER_WORKSPACE_ID]);
  });

  it("keeps the overview with spendUsd: null when OpenRouter fails", async () => {
    fakeActivity("fail");
    const err = vi.spyOn(console, "error").mockImplementation(() => {});
    expect((await overview()).ai).toEqual({ spendUsd: null, budgetUsd: 5, asOf: "2026-11-13" });
    expect(err).toHaveBeenCalled();
    err.mockRestore();
  });

  it("reads switches from the injected backend vars", async () => {
    fakeActivity([]);
    const result = await getOverview(createDb(env.DB), { ...env, SYNC_ENABLED: "false", AI_KEY_ENABLED: "nope" }, "r", NOW);
    expect(result.flags).toEqual({ sync: false, backup: true, aiKey: false });
  });
});

describe("GET /api/overview", () => {
  it("answers in one D1 batch (+1 guard) and one subrequest", async () => {
    const calls = fakeActivity([]);
    const { response, d1Queries } = await call("/api/overview", { headers: { cookie: await adminCookie() } });
    expect(response.status).toBe(200);
    // guard 1 + batch of 3 statements.
    expect(d1Queries).toBe(4);
    expect(calls).toHaveLength(1);
    expect(await response.json()).toMatchObject({ syncToday: { limit: 100_000 }, flags: { sync: true } });
  });
});
