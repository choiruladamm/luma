import { env } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { describe, expect, it, vi } from "vitest";
import { findUserKey } from "../../../backend/src/features/ai-key/repo";
import { createDb } from "../../../backend/src/db/client";
import { aiKeys, users } from "../../../backend/src/db/schema";
import { call, errorCode, ORIGIN } from "../helpers/app";
import { fakeOpenRouter } from "../helpers/openrouter";
import { adminCookie, createUser, giveUserData, sessionCookie } from "../helpers/session";

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
type Page = { items: Item[]; nextCursor: string | null };

const get = async (path: string) => call(path, { headers: { cookie: await adminCookie() } });
const post = async (path: string, overrides: Partial<Env> = {}) =>
  call(path, { method: "POST", headers: { cookie: await adminCookie(), "content-type": "application/json", origin: ORIGIN } }, overrides);

const db = () => createDb(env.DB);
const userRow = async (id: string) => (await db().select().from(users).where(eq(users.id, id)))[0]!;
const keyRow = async (id: string) => (await db().select().from(aiKeys).where(eq(aiKeys.userId, id)))[0] ?? null;

/** Unique email prefix per test, so searches don't hit other tests' data. */
const tag = () => `t${crypto.randomUUID().slice(0, 8)}`;

describe("GET /api/users", () => {
  it("lists newest first with cursor pagination in one D1 query (+1 guard)", async () => {
    const t = tag();
    const base = Date.UTC(2026, 10, 1);
    const ids = [];
    for (let i = 0; i < 5; i++) ids.push((await createUser({ email: `${t}-${i}@luma.test`, createdAt: new Date(base + i * 1000) })).id);

    const first = await get(`/api/users?q=${t}&limit=2`);
    expect(first.response.status).toBe(200);
    expect(first.d1Queries).toBe(2);
    const p1 = (await first.response.json()) as Page;
    expect(p1.items.map((u) => u.email)).toEqual([`${t}-4@luma.test`, `${t}-3@luma.test`]);

    const p2 = (await (await get(`/api/users?q=${t}&limit=2&cursor=${p1.nextCursor}`)).response.json()) as Page;
    const p3 = (await (await get(`/api/users?q=${t}&limit=2&cursor=${p2.nextCursor}`)).response.json()) as Page;
    expect(p2.items.map((u) => u.email)).toEqual([`${t}-2@luma.test`, `${t}-1@luma.test`]);
    expect(p3.items.map((u) => u.email)).toEqual([`${t}-0@luma.test`]);
    expect(p3.nextCursor).toBeNull();
  });

  it("keeps the same-millisecond tie stable through the cursor", async () => {
    const t = tag();
    const at = new Date(Date.UTC(2026, 10, 2));
    for (let i = 0; i < 3; i++) await createUser({ email: `${t}-${i}@luma.test`, createdAt: at });
    const seen: string[] = [];
    let cursor: string | null = "";
    while (cursor !== null) {
      const page = (await (await get(`/api/users?q=${t}&limit=1${cursor ? `&cursor=${cursor}` : ""}`)).response.json()) as Page;
      seen.push(...page.items.map((u) => u.email));
      cursor = page.nextCursor;
    }
    expect(seen.sort()).toEqual([0, 1, 2].map((i) => `${t}-${i}@luma.test`));
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
    ["bad cursor", "cursor=abc"],
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
    // guard 1 + batch of 4 statements.
    expect(d1Queries).toBe(5);
    expect(openrouter.calls).toEqual(["GET hash-detail"]);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body).toMatchObject({
      id: user.id,
      ai: { limit: 0.02, usageDaily: 0.004, expiresAt: "2026-12-14T00:00:00.000Z" },
      invite: { code: "LUMA-DTL1", usedAt: "2026-11-01T00:00:00.000Z" },
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
