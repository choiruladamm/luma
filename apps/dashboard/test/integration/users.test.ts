import { env } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { describe, expect, it, vi } from "vitest";
import { findUserKey } from "../../../backend/src/features/ai-key/repo";
import { createDb } from "../../../backend/src/db/client";
import { aiKeys, sessions, users } from "../../../backend/src/db/schema";
import { call, errorCode, ORIGIN } from "../helpers/app";
import { fakeOpenRouter } from "../helpers/openrouter";
import { adminCookie, createGoogleUser, createUser, giveUserData, sessionCookie } from "../helpers/session";

type Item = {
  id: string;
  email: string;
  createdAt: string;
  lastActiveAt: string | null;
  banned: boolean;
  hasAiKey: boolean;
  r2Bytes: number;
  syncBytes: number;
};
type Page = { items: Item[]; total: number; page: number; pageCount: number };

const get = async (path: string) => call(path, { headers: { cookie: await adminCookie() } });
const post = async (path: string, overrides: Partial<Env> = {}) =>
  call(path, { method: "POST", headers: { cookie: await adminCookie(), "content-type": "application/json", origin: ORIGIN } }, overrides);

const db = () => createDb(env.DB);
const userRow = async (id: string) => (await db().select().from(users).where(eq(users.id, id)))[0]!;
const keyRow = async (id: string) => (await db().select().from(aiKeys).where(eq(aiKeys.userId, id)))[0] ?? null;

/** Unique email prefix per test, so searches don't hit other tests' data. */
const tag = () => `t${crypto.randomUUID().slice(0, 8)}`;

describe("GET /api/users", () => {
  it("pages newest first with a total in one D1 batch (+1 guard)", async () => {
    const t = tag();
    const base = Date.UTC(2026, 10, 1);
    for (let i = 0; i < 5; i++) await createUser({ email: `${t}-${i}@luma.test`, createdAt: new Date(base + i * 1000) });

    const first = await get(`/api/users?q=${t}&sort=created&limit=2`);
    expect(first.response.status).toBe(200);
    expect(first.d1Queries).toBe(3);
    const p1 = (await first.response.json()) as Page;
    expect(p1).toMatchObject({ total: 5, page: 1, pageCount: 3 });
    expect(p1.items.map((u) => u.email)).toEqual([`${t}-4@luma.test`, `${t}-3@luma.test`]);

    const p3 = (await (await get(`/api/users?q=${t}&sort=created&limit=2&page=3`)).response.json()) as Page;
    expect(p3.items.map((u) => u.email)).toEqual([`${t}-0@luma.test`]);
    const asc = (await (await get(`/api/users?q=${t}&sort=created&dir=asc&limit=2`)).response.json()) as Page;
    expect(asc.items.map((u) => u.email)).toEqual([`${t}-0@luma.test`, `${t}-1@luma.test`]);
    const past = (await (await get(`/api/users?q=${t}&limit=2&page=9`)).response.json()) as Page;
    expect(past).toMatchObject({ items: [], total: 5, pageCount: 3 });
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
    await db().insert(sessions).values({ id: crypto.randomUUID(), token: crypto.randomUUID(), userId: old.id, expiresAt: tenDaysAgo, createdAt: tenDaysAgo, updatedAt: tenDaysAgo });

    const emails = async (filter: string) => {
      const page = (await (await get(`/api/users?q=${t}&${filter}`)).response.json()) as Page;
      expect(page.total).toBe(page.items.length);
      return page.items.map((u) => u.email.replace(`${t}-`, "").replace("@luma.test", "")).sort();
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
    await db().insert(sessions).values({ id: crypto.randomUUID(), token: crypto.randomUUID(), userId: small.id, expiresAt: dayAgo, createdAt: dayAgo, updatedAt: dayAgo });

    const order = async (query: string) =>
      ((await (await get(`/api/users?q=${t}&${query}`)).response.json()) as Page).items.map((u) => u.email.replace(`${t}-`, "").replace("@luma.test", ""));
    expect(await order("sort=r2")).toEqual(["big", "small", "idle"]);
    expect(await order("sort=r2&dir=asc")).toEqual(["idle", "small", "big"]);
    expect(await order("sort=sync")).toEqual(["small", "big", "idle"]);
    expect(await order("sort=lastActive")).toEqual(["big", "small", "idle"]);
    expect(await order("sort=lastActive&dir=asc")).toEqual(["small", "big", idle.email.replace(`${t}-`, "").replace("@luma.test", "")]);
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
    expect(items.find((u) => u.id === bare.id)).toMatchObject({ hasAiKey: false, r2Bytes: 0, syncBytes: 0, lastActiveAt: null, banned: false });
    expect(items.find((u) => u.id === full.id)).toMatchObject({ hasAiKey: true, r2Bytes: 1234, syncBytes: 99 });
    expect(items.find((u) => u.id === full.id)?.lastActiveAt).toMatch(/Z$/);
  });

  it("finds q anywhere in the email or name, best match first, across pages", async () => {
    const t = tag();
    const at = (min: number) => new Date(Date.UTC(2026, 10, 1, 0, min));
    // Created oldest → newest; the ranking, not the date, decides the order.
    await createUser({ email: `${t}zz@luma.test`, createdAt: at(1) }); // 1: email prefix
    await createUser({ email: `ab${t}@luma.test`, createdAt: at(2) }); // 3: inside a word
    await createUser({ email: `x.${t}@luma.test`, createdAt: at(3) }); // 2: word start in the email
    await createUser({ email: `nm${crypto.randomUUID().slice(0, 6)}@luma.test`, name: `Putri ${t}`, createdAt: at(4) }); // 2: word of the name
    const expected = [`${t}zz@luma.test`, "name", `x.${t}@luma.test`, `ab${t}@luma.test`];
    const label = (u: Item) => (u.email.startsWith("nm") ? "name" : u.email);

    const page = (await (await get(`/api/users?q=${t.toUpperCase()}`)).response.json()) as Page;
    expect(page.items.map(label)).toEqual(expected);

    const exact = (await (await get(`/api/users?q=${t}zz@luma.test`)).response.json()) as Page;
    expect(exact.items[0]!.email).toBe(`${t}zz@luma.test`);

    // Relevance holds across pages too.
    const seen: string[] = [];
    for (let page = 1; page <= 4; page++) {
      const p = (await (await get(`/api/users?q=${t}&limit=1&page=${page}`)).response.json()) as Page;
      seen.push(...p.items.map(label));
    }
    expect(seen).toEqual(expected);
  });

  it("treats % and _ in q as literal characters", async () => {
    const t = tag();
    await createUser({ email: `${t}_a@luma.test` });
    await createUser({ email: `${t}xa@luma.test` });
    const page = (await (await get(`/api/users?q=${t}_`)).response.json()) as Page;
    expect(page.items.map((u) => u.email)).toEqual([`${t}_a@luma.test`]);
    const pct = (await (await get(`/api/users?q=${t}%25`)).response.json()) as Page;
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
    expect(openrouter.calls).toEqual(["GET hash-detail"]);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body).toMatchObject({
      id: user.id,
      ai: { limit: 0.02, usageDaily: 0.004, expiresAt: "2026-12-14T00:00:00.000Z" },
      invite: { code: "LUMA-DTL1", usedAt: "2026-11-01T00:00:00.000Z" },
      providers: [],
    });
    expect((body.sessions as unknown[])[0]).toEqual({
      userAgent: null,
      ipAddress: null,
      createdAt: expect.stringMatching(/Z$/),
      updatedAt: expect.stringMatching(/Z$/),
    });
    expect(JSON.stringify(body)).not.toMatch(/keyEnc|rahasia-terenkripsi|token|hash-detail/);
  });

  it("returns ai: null without any subrequest when the user has no key", async () => {
    const user = await createUser();
    const openrouter = fakeOpenRouter();
    const body = (await (await get(`/api/users/${user.id}`)).response.json()) as Record<string, unknown>;
    expect(body.ai).toBeNull();
    expect(body.invite).toBeNull();
    expect(openrouter.calls).toEqual([]);
  });

  it("keeps the detail open with usageDaily: null when OpenRouter fails", async () => {
    const user = await createUser();
    await giveUserData(user.id, { keyHash: "hash-down" });
    fakeOpenRouter({ fail: true });
    const err = vi.spyOn(console, "error").mockImplementation(() => {});

    const { response } = await get(`/api/users/${user.id}`);
    expect(response.status).toBe(200);
    expect(((await response.json()) as { ai: unknown }).ai).toMatchObject({ usageDaily: null, limit: 0.02 });
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
    expect(await response.json()).toEqual({ banned: true, keyRevoked: true });
    // guard 1 + key lookup 1 + batch of 2 statements.
    expect(d1Queries).toBe(4);
    expect(openrouter.calls).toEqual(["DELETE hash-ban"]);
    expect(openrouter.live.has("hash-ban")).toBe(false);
    expect((await userRow(user.id)).banned).toBe(true);
    expect(await keyRow(user.id)).toBeNull();
    const audit = log.mock.calls.map((c) => JSON.parse(c[0] as string)).find((l) => l.message === "audit");
    expect(audit).toMatchObject({ action: "user.ban", targetId: user.id, admin: "admin@luma.test" });
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

    expect(await (await post(`/api/users/${user.id}/ban`)).response.json()).toEqual({ banned: true, keyRevoked: true });
    expect(await (await post(`/api/users/${user.id}/ban`)).response.json()).toEqual({ banned: true, keyRevoked: false });
    expect(openrouter.calls).toEqual(["DELETE hash-dua"]);

    const noKey = await createUser();
    const res = await post(`/api/users/${noKey.id}/ban`);
    expect(await res.response.json()).toEqual({ banned: true, keyRevoked: false });
    expect((await userRow(noKey.id)).banned).toBe(true);
  });

  it("treats a key already gone at OpenRouter (404) as revoked", async () => {
    const user = await createUser();
    await giveUserData(user.id, { keyHash: "hash-hilang" });
    fakeOpenRouter();
    const { response } = await post(`/api/users/${user.id}/ban`);
    expect(await response.json()).toEqual({ banned: true, keyRevoked: true });
  });

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
    expect(log.mock.calls.map((c) => JSON.parse(c[0] as string)).find((l) => l.message === "audit")).toMatchObject({
      action: "user.unban",
      targetId: user.id,
    });
    log.mockRestore();
  });

  it("answers 404 for an unknown user", async () => {
    const { response } = await post("/api/users/gak-ada/unban");
    expect(response.status).toBe(404);
  });
});

describe("admin mutation rate limit", () => {
  it("answers 429 per admin before touching the user", async () => {
    const user = await createUser();
    const keys: string[] = [];
    const deny = { limit: async ({ key }: { key: string }) => (keys.push(key), { success: false }) } as unknown as RateLimit;
    const { response } = await post(`/api/users/${user.id}/ban`, { ADMIN_RATE_LIMITER: deny });
    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("60");
    expect(keys[0]).toMatch(/^admin:/);
    expect((await userRow(user.id)).banned).toBe(false);
  });

  it("does not limit reads", async () => {
    const deny = { limit: async () => ({ success: false }) } as unknown as RateLimit;
    const { response } = await call("/api/users", { headers: { cookie: await adminCookie() } }, { ADMIN_RATE_LIMITER: deny });
    expect(response.status).toBe(200);
  });
});

describe("GET /api/users/:id providers", () => {
  it("lists the sign-in providers of the account", async () => {
    const user = await createGoogleUser(`prov-${crypto.randomUUID().slice(0, 6)}@luma.test`);
    const body = (await (await get(`/api/users/${user.id}`)).response.json()) as { providers: string[] };
    expect(body.providers).toEqual(["google"]);
  });
});
