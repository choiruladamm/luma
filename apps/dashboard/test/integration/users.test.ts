import { env } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { describe, expect, it, vi } from "vitest";
import { findUserKey } from "@luma/core/ai-keys";
import { createDb } from "@luma/core/db/client";
import { aiKeys, sessions, usageDaily, users } from "@luma/core/db/schema";
import { call, errorCode, ORIGIN } from "../helpers/app";
import { fakeOpenRouter } from "../helpers/openrouter";
import {
  adminCookie,
  createGoogleUser,
  createUser,
  giveUserData,
  sessionCookie,
} from "../helpers/session";

type Item = {
  id: string;
  email: string;
  created_at: string;
  last_active_at: string | null;
  banned: boolean;
  has_ai_key: boolean;
  r2_bytes: number;
  sync_bytes: number;
};
type Page = { items: Item[]; total: number; page: number; page_count: number };

const get = async (path: string) => call(path, { headers: { cookie: await adminCookie() } });
const post = async (path: string, overrides: Partial<Env> = {}) =>
  call(
    path,
    {
      method: "POST",
      headers: { cookie: await adminCookie(), "content-type": "application/json", origin: ORIGIN },
    },
    overrides,
  );

const db = () => createDb(env.DB);
const userRow = async (id: string) => (await db().select().from(users).where(eq(users.id, id)))[0]!;
const keyRow = async (id: string) =>
  (await db().select().from(aiKeys).where(eq(aiKeys.userId, id)))[0] ?? null;

/** Unique email prefix per test, so searches don't hit other tests' data. */
const tag = () => `t${crypto.randomUUID().slice(0, 8)}`;

describe("GET /api/users", () => {
  it("pages newest first with a total in one D1 batch (+1 guard)", async () => {
    const t = tag();
    const base = Date.UTC(2026, 10, 1);
    for (let i = 0; i < 5; i++)
      await createUser({ email: `${t}-${i}@luma.test`, createdAt: new Date(base + i * 1000) });

    const first = await get(`/api/users?q=${t}&sort=created&limit=2`);
    expect(first.response.status).toBe(200);
    expect(first.d1Queries).toBe(3);
    const p1 = await first.response.json<Page>();
    expect(p1).toMatchObject({ total: 5, page: 1, page_count: 3 });
    expect(p1.items.map((u) => u.email)).toEqual([`${t}-4@luma.test`, `${t}-3@luma.test`]);

    const p3 = await (
      await get(`/api/users?q=${t}&sort=created&limit=2&page=3`)
    ).response.json<Page>();
    expect(p3.items.map((u) => u.email)).toEqual([`${t}-0@luma.test`]);
    const asc = await (
      await get(`/api/users?q=${t}&sort=created&dir=asc&limit=2`)
    ).response.json<Page>();
    expect(asc.items.map((u) => u.email)).toEqual([`${t}-0@luma.test`, `${t}-1@luma.test`]);
    const past = await (await get(`/api/users?q=${t}&limit=2&page=9`)).response.json<Page>();
    expect(past).toMatchObject({ items: [], total: 5, page_count: 3 });
  });

  it("filters by ban status, subsidized key, and activity window, and counts the filtered total", async () => {
    const t = tag();
    const banned = await createUser({ email: `${t}-banned@luma.test` });
    await db().update(users).set({ banned: true }).where(eq(users.id, banned.id));
    const keyed = await createUser({ email: `${t}-key@luma.test` });
    await giveUserData(keyed.id, { keyHash: `hash-${t}` });
    const recent = await createUser({ email: `${t}-recent@luma.test` });
    await sessionCookie(recent.id);
    const old = await createUser({ email: `${t}-old@luma.test` });
    const tenDaysAgo = new Date(Date.now() - 10 * 86_400_000);
    await db().insert(sessions).values({
      id: crypto.randomUUID(),
      token: crypto.randomUUID(),
      userId: old.id,
      expiresAt: tenDaysAgo,
      createdAt: tenDaysAgo,
      updatedAt: tenDaysAgo,
    });

    const emails = async (filter: string) => {
      const page = await (await get(`/api/users?q=${t}&${filter}`)).response.json<Page>();
      expect(page.total).toBe(page.items.length);
      return page.items
        .map((u) => u.email.replace(`${t}-`, "").replace("@luma.test", ""))
        .toSorted();
    };
    expect(await emails("status=banned")).toEqual(["banned"]);
    expect(await emails("status=active")).toEqual(["key", "old", "recent"]);
    expect(await emails("ai=yes")).toEqual(["key"]);
    expect(await emails("ai=no")).toEqual(["banned", "old", "recent"]);
    expect(await emails("activity=7d")).toEqual(["recent"]);
    expect(await emails("activity=30d")).toEqual(["old", "recent"]);
    expect(await emails("activity=never")).toEqual(["banned", "key"]);
    expect(await emails("status=active&activity=never")).toEqual(["key"]);
  });

  it("sorts by files, sync data, and last active (never-active last both ways)", async () => {
    const t = tag();
    const small = await createUser({ email: `${t}-small@luma.test` });
    await giveUserData(small.id, { r2Bytes: 10, syncBytes: 300 });
    const big = await createUser({ email: `${t}-big@luma.test` });
    await giveUserData(big.id, { r2Bytes: 999, syncBytes: 5 });
    const idle = await createUser({ email: `${t}-idle@luma.test` });
    await sessionCookie(big.id);
    const dayAgo = new Date(Date.now() - 86_400_000);
    await db().insert(sessions).values({
      id: crypto.randomUUID(),
      token: crypto.randomUUID(),
      userId: small.id,
      expiresAt: dayAgo,
      createdAt: dayAgo,
      updatedAt: dayAgo,
    });

    const order = async (query: string) =>
      (await (await get(`/api/users?q=${t}&${query}`)).response.json<Page>()).items.map((u) =>
        u.email.replace(`${t}-`, "").replace("@luma.test", ""),
      );
    expect(await order("sort=r2")).toEqual(["big", "small", "idle"]);
    expect(await order("sort=r2&dir=asc")).toEqual(["idle", "small", "big"]);
    expect(await order("sort=sync")).toEqual(["small", "big", "idle"]);
    expect(await order("sort=lastActive")).toEqual(["big", "small", "idle"]);
    expect(await order("sort=lastActive&dir=asc")).toEqual([
      "small",
      "big",
      idle.email.replace(`${t}-`, "").replace("@luma.test", ""),
    ]);
  });

  it("returns users without storage, key, or sessions, and never leaks keyEnc or tokens", async () => {
    const t = tag();
    const bare = await createUser({ email: `${t}-bare@luma.test` });
    const full = await createUser({ email: `${t}-full@luma.test` });
    await giveUserData(full.id, { keyHash: "hash-full", r2Bytes: 1234, syncBytes: 99 });
    await sessionCookie(full.id);

    const { response } = await get(`/api/users?q=${t}`);
    const text = await response.text();
    expect(text).not.toMatch(/keyEnc|key_enc|rahasia-terenkripsi|token|keyHash|hash-full/);
    const items = (JSON.parse(text) as Page).items;
    expect(items.find((u) => u.id === bare.id)).toMatchObject({
      has_ai_key: false,
      r2_bytes: 0,
      sync_bytes: 0,
      last_active_at: null,
      banned: false,
    });
    expect(items.find((u) => u.id === full.id)).toMatchObject({
      has_ai_key: true,
      r2_bytes: 1234,
      sync_bytes: 99,
    });
    expect(items.find((u) => u.id === full.id)?.last_active_at).toMatch(/Z$/);
  });

  it("finds q anywhere in the email or name, best match first, across pages", async () => {
    const t = tag();
    const at = (min: number) => new Date(Date.UTC(2026, 10, 1, 0, min));
    // Created oldest → newest; the ranking, not the date, decides the order.
    await createUser({ email: `${t}zz@luma.test`, createdAt: at(1) }); // 1: email prefix
    await createUser({ email: `ab${t}@luma.test`, createdAt: at(2) }); // 3: inside a word
    await createUser({ email: `x.${t}@luma.test`, createdAt: at(3) }); // 2: word start in the email
    await createUser({
      email: `nm${crypto.randomUUID().slice(0, 6)}@luma.test`,
      name: `Putri ${t}`,
      createdAt: at(4),
    }); // 2: word of the name
    const expected = [`${t}zz@luma.test`, "name", `x.${t}@luma.test`, `ab${t}@luma.test`];
    const label = (u: Item) => (u.email.startsWith("nm") ? "name" : u.email);

    const page = await (await get(`/api/users?q=${t.toUpperCase()}`)).response.json<Page>();
    expect(page.items.map(label)).toEqual(expected);

    const exact = await (await get(`/api/users?q=${t}zz@luma.test`)).response.json<Page>();
    expect(exact.items[0]!.email).toBe(`${t}zz@luma.test`);

    // Relevance holds across pages too.
    const seen: string[] = [];
    for (let n = 1; n <= 4; n++) {
      const p = await (await get(`/api/users?q=${t}&limit=1&page=${n}`)).response.json<Page>();
      seen.push(...p.items.map(label));
    }
    expect(seen).toEqual(expected);
  });

  it("handles a search as long as the limit allows (D1 caps LIKE patterns at 50 bytes)", async () => {
    const t = tag();
    const long = `${t}${"x".repeat(60)}`;
    await createUser({ email: `${long}@luma.test` });
    const { response } = await get(`/api/users?q=${long}`);
    expect(response.status).toBe(200);
    expect((await response.json<Page>()).items.map((u) => u.email)).toEqual([`${long}@luma.test`]);
    expect((await get(`/api/users?q=${"z".repeat(100)}`)).response.status).toBe(200);
  });

  it("treats % and _ in q as literal characters", async () => {
    const t = tag();
    await createUser({ email: `${t}_a@luma.test` });
    await createUser({ email: `${t}xa@luma.test` });
    const page = await (await get(`/api/users?q=${t}_`)).response.json<Page>();
    expect(page.items.map((u) => u.email)).toEqual([`${t}_a@luma.test`]);
    const pct = await (await get(`/api/users?q=${t}%25`)).response.json<Page>();
    expect(pct.items).toEqual([]);
  });

  it.each([
    ["q over 100 chars", `q=${"a".repeat(101)}`],
    ["limit over 50", "limit=51"],
    ["limit 0", "limit=0"],
    ["bad status", "status=gone"],
    ["bad sort", "sort=email"],
    ["bad dir", "dir=up"],
    ["page 0", "page=0"],
  ])("answers 400 for %s", async (_, query) => {
    const { response } = await get(`/api/users?${query}`);
    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe("BAD_REQUEST");
  });
});

describe("GET /api/users/:id/usage", () => {
  const today = new Date().toISOString().slice(0, 10);
  const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString().slice(0, 10);
  const row = (userId: string, over: Partial<typeof usageDaily.$inferInsert>) => ({
    userId,
    day: today,
    feature: "group",
    model: "m1",
    bookKey: "b1",
    bookTitle: "Meditations",
    keySource: "subsidy",
    calls: 10,
    failed: 1,
    promptTokens: 1000,
    completionTokens: 200,
    costUsd: 0.01,
    readingSeconds: 0,
    updatedAt: 0,
    ...over,
  });

  it("sums the rollup per feature, model, key source, and book in one D1 batch", async () => {
    const user = await createUser();
    const other = await createUser();
    await db()
      .insert(usageDaily)
      .values([
        row(user.id, {}),
        row(user.id, { feature: "chat", model: "m2", keySource: "own", costUsd: null }),
        row(user.id, {
          feature: "reading",
          model: "",
          keySource: "",
          calls: 0,
          failed: 0,
          promptTokens: 0,
          completionTokens: 0,
          costUsd: null,
          readingSeconds: 600,
        }),
        row(user.id, { day: daysAgo(1), bookKey: "b2", bookTitle: "Catatan", calls: 2, failed: 0 }),
        // Outside the 30-day range: only counts as the last day if nothing newer exists.
        row(user.id, { day: daysAgo(40), calls: 99 }),
        row(other.id, { calls: 500 }),
      ]);

    const { response, d1Queries } = await get(`/api/users/${user.id}/usage`);

    expect(response.status).toBe(200);
    // guard 1 + batch of 6 statements.
    expect(d1Queries).toBe(7);
    expect(await response.json()).toEqual({
      from: daysAgo(29),
      to: today,
      totals: {
        calls: 22,
        failed: 2,
        cost_usd: 0.02,
        prompt_tokens: 3000,
        completion_tokens: 600,
        reading_seconds: 600,
        active_days: 2,
        last_day: today,
      },
      features: [
        {
          feature: "group",
          calls: 12,
          failed: 1,
          cost_usd: 0.02,
          prompt_tokens: 2000,
          completion_tokens: 400,
        },
        {
          feature: "chat",
          calls: 10,
          failed: 1,
          cost_usd: null,
          prompt_tokens: 1000,
          completion_tokens: 200,
        },
      ],
      models: [
        { model: "m1", calls: 12, failed: 1, cost_usd: 0.02 },
        { model: "m2", calls: 10, failed: 1, cost_usd: null },
      ],
      key_sources: [
        { key_source: "subsidy", calls: 12, failed: 1, cost_usd: 0.02 },
        { key_source: "own", calls: 10, failed: 1, cost_usd: null },
      ],
      books: [
        {
          book_key: "b1",
          book_title: "Meditations",
          reading_seconds: 600,
          calls: 20,
          failed: 2,
          cost_usd: 0.01,
        },
        {
          book_key: "b2",
          book_title: "Catatan",
          reading_seconds: 0,
          calls: 2,
          failed: 0,
          cost_usd: 0.01,
        },
      ],
    });
  });

  it("returns zeros for a user who never sent usage, and honours days", async () => {
    const user = await createUser();
    const body = await (await get(`/api/users/${user.id}/usage?days=7`)).response.json();
    expect(body).toEqual({
      from: daysAgo(6),
      to: today,
      totals: {
        calls: 0,
        failed: 0,
        cost_usd: null,
        prompt_tokens: 0,
        completion_tokens: 0,
        reading_seconds: 0,
        active_days: 0,
        last_day: null,
      },
      features: [],
      models: [],
      key_sources: [],
      books: [],
    });
  });

  it("rejects a bad range and answers 404 for an unknown user", async () => {
    const user = await createUser();
    for (const days of ["0", "366", "x"]) {
      const { response } = await get(`/api/users/${user.id}/usage?days=${days}`);
      expect(response.status).toBe(400);
    }
    const missing = await get("/api/users/nobody/usage");
    expect(missing.response.status).toBe(404);
    expect(await errorCode(missing.response)).toBe("NOT_FOUND");
  });
});

describe("GET /api/users/:id", () => {
  it("returns sessions, AI usage (1 subrequest), and invite in one D1 batch", async () => {
    const user = await createUser();
    await giveUserData(user.id, { keyHash: "hash-detail", invite: "LUMA-DTL1" });
    await sessionCookie(user.id);
    const openrouter = fakeOpenRouter({ keys: ["hash-detail"] });

    const { response, d1Queries } = await get(`/api/users/${user.id}`);
    expect(response.status).toBe(200);
    // guard 1 + batch of 5 statements.
    expect(d1Queries).toBe(6);
    expect(openrouter.calls).toEqual(["GET /keys/hash-detail"]);
    const body = await response.json<Record<string, unknown>>();
    expect(body).toMatchObject({
      id: user.id,
      ai: { limit: 0.02, usage_daily: 0.004, expires_at: "2026-12-14T00:00:00.000Z" },
      invite: { code: "LUMA-DTL1", used_at: "2026-11-01T00:00:00.000Z" },
      providers: [],
    });
    expect((body.sessions as unknown[])[0]).toEqual({
      user_agent: null,
      ip_address: null,
      created_at: expect.stringMatching(/Z$/),
      updated_at: expect.stringMatching(/Z$/),
    });
    expect(JSON.stringify(body)).not.toMatch(/keyEnc|rahasia-terenkripsi|token|hash-detail/);
  });

  it("returns ai: null without any subrequest when the user has no key", async () => {
    const user = await createUser();
    const openrouter = fakeOpenRouter();
    const body = await (
      await get(`/api/users/${user.id}`)
    ).response.json<Record<string, unknown>>();
    expect(body.ai).toBeNull();
    expect(body.invite).toBeNull();
    expect(openrouter.calls).toEqual([]);
  });

  it("keeps the detail open with usage_daily: null when OpenRouter fails", async () => {
    const user = await createUser();
    await giveUserData(user.id, { keyHash: "hash-down" });
    fakeOpenRouter({ fail: true });
    const err = vi.spyOn(console, "error").mockImplementation(() => {});

    const { response } = await get(`/api/users/${user.id}`);
    expect(response.status).toBe(200);
    expect((await response.json<{ ai: unknown }>()).ai).toMatchObject({
      usage_daily: null,
      limit: 0.02,
    });
    expect(err).toHaveBeenCalled();
    err.mockRestore();
  });

  it("answers 404 for an unknown user and 400 for a malformed id", async () => {
    const missing = await get("/api/users/gak-ada");
    expect(missing.response.status).toBe(404);
    expect(await errorCode(missing.response)).toBe("NOT_FOUND");
    expect((await get("/api/users/bad%20id")).response.status).toBe(400);
  });
});

describe("POST /api/users/:id/ban", () => {
  it("revokes the OpenRouter key first, then bans + deletes ai_keys (audit, budget)", async () => {
    const user = await createUser();
    await giveUserData(user.id, { keyHash: "hash-ban" });
    const openrouter = fakeOpenRouter({ keys: ["hash-ban"] });
    const log = vi.spyOn(console, "log").mockImplementation(() => {});

    const { response, d1Queries } = await post(`/api/users/${user.id}/ban`);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ banned: true, key_revoked: true });
    // guard 1 + key lookup 1 + batch of 2 statements.
    expect(d1Queries).toBe(4);
    expect(openrouter.calls).toEqual(["DELETE /keys/hash-ban"]);
    expect(openrouter.keys.has("hash-ban")).toBe(false);
    expect((await userRow(user.id)).banned).toBe(true);
    expect(await keyRow(user.id)).toBeNull();
    const audit = log.mock.calls
      .map((c) => JSON.parse(c[0] as string))
      .find((l) => l.message === "audit");
    expect(audit).toMatchObject({
      action: "user.ban",
      target_id: user.id,
      admin: "admin@luma.test",
    });
    log.mockRestore();
  });

  it("answers 502 and leaves D1 untouched when OpenRouter fails", async () => {
    const user = await createUser();
    await giveUserData(user.id, { keyHash: "hash-gagal" });
    fakeOpenRouter({ fail: true });

    const { response } = await post(`/api/users/${user.id}/ban`);
    expect(response.status).toBe(502);
    expect(await errorCode(response)).toBe("OPENROUTER_FAILED");
    expect((await userRow(user.id)).banned).toBe(false);
    expect(await keyRow(user.id)).not.toBeNull();
  });

  it("is idempotent and works for a user without a key", async () => {
    const user = await createUser();
    await giveUserData(user.id, { keyHash: "hash-dua" });
    const openrouter = fakeOpenRouter({ keys: ["hash-dua"] });

    expect(await (await post(`/api/users/${user.id}/ban`)).response.json()).toEqual({
      banned: true,
      key_revoked: true,
    });
    expect(await (await post(`/api/users/${user.id}/ban`)).response.json()).toEqual({
      banned: true,
      key_revoked: false,
    });
    expect(openrouter.calls).toEqual(["DELETE /keys/hash-dua"]);

    const noKey = await createUser();
    const res = await post(`/api/users/${noKey.id}/ban`);
    expect(await res.response.json()).toEqual({ banned: true, key_revoked: false });
    expect((await userRow(noKey.id)).banned).toBe(true);
  });

  it("treats a key already gone at OpenRouter (404) as revoked", async () => {
    const user = await createUser();
    await giveUserData(user.id, { keyHash: "hash-hilang" });
    fakeOpenRouter();
    const { response } = await post(`/api/users/${user.id}/ban`);
    expect(await response.json()).toEqual({ banned: true, key_revoked: true });
  });

  it.each(["ban", "unban"])(
    "%s answers 400 for a malformed id without touching D1 or OpenRouter",
    async (action) => {
      const openrouter = fakeOpenRouter();
      const { response, d1Queries } = await post(`/api/users/bad%20id/${action}`);
      expect(response.status).toBe(400);
      // guard only.
      expect(d1Queries).toBe(1);
      expect(openrouter.calls).toEqual([]);
    },
  );

  it("answers 404 for an unknown user without calling OpenRouter", async () => {
    const openrouter = fakeOpenRouter();
    const { response } = await post("/api/users/gak-ada/ban");
    expect(response.status).toBe(404);
    expect(openrouter.calls).toEqual([]);
  });
});

describe("POST /api/users/:id/unban", () => {
  it("clears banned in one query so the backend issues a key again (audit)", async () => {
    const user = await createUser();
    await giveUserData(user.id, { keyHash: "hash-unban" });
    fakeOpenRouter({ keys: ["hash-unban"] });
    await post(`/api/users/${user.id}/ban`);
    expect((await findUserKey(db(), user.id)).banned).toBe(true);
    const log = vi.spyOn(console, "log").mockImplementation(() => {});

    const { response, d1Queries } = await post(`/api/users/${user.id}/unban`);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ banned: false });
    expect(d1Queries).toBe(2);
    // What the backend `issueKey` reads before creating a key (banned → 403 AI_BANNED).
    expect(await findUserKey(db(), user.id)).toEqual({ banned: false, key: null });
    expect(
      log.mock.calls.map((c) => JSON.parse(c[0] as string)).find((l) => l.message === "audit"),
    ).toMatchObject({
      action: "user.unban",
      target_id: user.id,
    });
    log.mockRestore();
  });

  it("answers 404 for an unknown user", async () => {
    const { response } = await post("/api/users/gak-ada/unban");
    expect(response.status).toBe(404);
  });
});

describe("audit trail", () => {
  // The trail records what happened: a mutation that failed must leave no line behind.
  it("logs nothing for a ban OpenRouter rejects or a user or invite that doesn't exist", async () => {
    const user = await createUser();
    await giveUserData(user.id, { keyHash: "hash-audit" });
    fakeOpenRouter({ fail: true });
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const error = vi.spyOn(console, "error").mockImplementation(() => {});

    expect((await post(`/api/users/${user.id}/ban`)).response.status).toBe(502);
    expect((await post("/api/users/gak-ada/ban")).response.status).toBe(404);
    expect((await post("/api/users/gak-ada/unban")).response.status).toBe(404);
    const missingInvite = await call("/api/invites/LUMA-ZZZZZ-ZZZZZ", {
      method: "DELETE",
      headers: { cookie: await adminCookie(), "content-type": "application/json", origin: ORIGIN },
    });
    expect(missingInvite.response.status).toBe(404);

    const lines = log.mock.calls.map((c) => JSON.parse(c[0] as string) as { message: string });
    expect(lines.filter((l) => l.message === "audit")).toEqual([]);
    log.mockRestore();
    error.mockRestore();
  });
});

describe("admin mutation rate limit", () => {
  it("answers 429 per admin before touching the user", async () => {
    const user = await createUser();
    const keys: string[] = [];
    const deny = {
      limit: async ({ key }: { key: string }) => (keys.push(key), { success: false }),
    };
    const { response } = await post(`/api/users/${user.id}/ban`, { ADMIN_RATE_LIMITER: deny });
    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("60");
    expect(keys[0]).toMatch(/^admin:/);
    expect((await userRow(user.id)).banned).toBe(false);
  });

  it("limits invite mutations the same way", async () => {
    const deny = { limit: async () => ({ success: false }) };
    const headers = {
      cookie: await adminCookie(),
      "content-type": "application/json",
      origin: ORIGIN,
    };
    const created = await call(
      "/api/invites",
      { method: "POST", headers, body: JSON.stringify({ count: 1 }) },
      { ADMIN_RATE_LIMITER: deny },
    );
    expect(created.response.status).toBe(429);
    const deleted = await call(
      "/api/invites/LUMA-AAAAA-BBBBB",
      { method: "DELETE", headers },
      { ADMIN_RATE_LIMITER: deny },
    );
    expect(deleted.response.status).toBe(429);
  });

  it("does not limit reads", async () => {
    const deny = { limit: async () => ({ success: false }) };
    const { response } = await call(
      "/api/users",
      { headers: { cookie: await adminCookie() } },
      { ADMIN_RATE_LIMITER: deny },
    );
    expect(response.status).toBe(200);
  });
});

describe("GET /api/users/:id providers", () => {
  it("lists the sign-in providers of the account", async () => {
    const user = await createGoogleUser(`prov-${crypto.randomUUID().slice(0, 6)}@luma.test`);
    const body = await (
      await get(`/api/users/${user.id}`)
    ).response.json<{
      providers: string[];
    }>();
    expect(body.providers).toEqual(["google"]);
  });
});
