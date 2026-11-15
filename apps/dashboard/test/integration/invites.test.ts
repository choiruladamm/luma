import { env } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { describe, expect, it, vi } from "vitest";
import { consumeInviteCode, normalizeInviteCode } from "../../../backend/src/auth/invite";
import { createDb } from "../../../backend/src/db/client";
import { inviteCodes } from "../../../backend/src/db/schema";
import { displayInviteCode } from "../../worker/features/invites/service";
import { call, errorCode, ORIGIN } from "../helpers/app";
import { adminCookie, createUser, giveUserData } from "../helpers/session";

type Item = { code: string; usedBy: { id: string; email: string } | null; usedAt: string | null };

const mutate = async (method: string, path: string, body?: unknown) =>
  call(path, {
    method,
    headers: { cookie: await adminCookie(), "content-type": "application/json", origin: ORIGIN },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
type Page = { items: Item[]; total: number; page: number; pageCount: number; counts: { all: number; unused: number; used: number } };
const page = async (query = "") => (await (await call(`/api/invites${query}`, { headers: { cookie: await adminCookie() } })).response.json()) as Page;
const list = async (query = "") => (await page(query)).items;
const db = () => createDb(env.DB);
/** Codes stored as given (already upper case); a unique tag keeps each test's rows apart. */
const tag = () => crypto.randomUUID().replaceAll("-", "").slice(0, 6).toUpperCase();
const DAY = 86_400_000;
const stored = async (code: string) =>
  (await createDb(env.DB).select().from(inviteCodes).where(eq(inviteCodes.code, normalizeInviteCode(code))))[0] ?? null;

describe("POST /api/invites", () => {
  it("creates codes in one insert that the backend sign-up accepts (audit)", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const { response, d1Queries } = await mutate("POST", "/api/invites", { count: 3 });
    expect(response.status).toBe(201);
    const { codes } = (await response.json()) as { codes: string[] };
    expect(codes).toHaveLength(3);
    for (const code of codes) expect(code).toMatch(/^LUMA-[2-9A-HJ-NP-Z]{5}-[2-9A-HJ-NP-Z]{5}$/);
    // guard 1 + 1 insert.
    expect(d1Queries).toBe(2);

    // What /v1/auth sign-up runs on the code the user types (any case, with or without dashes).
    expect(await consumeInviteCode(createDb(env.DB), codes[0]!.toLowerCase())).toBe("ok");
    expect(await consumeInviteCode(createDb(env.DB), codes[1]!.replaceAll("-", ""))).toBe("ok");
    expect(log.mock.calls.map((c) => JSON.parse(c[0] as string)).find((l) => l.message === "audit")).toMatchObject({
      action: "invite.create",
      targetId: codes.join(","),
    });
    log.mockRestore();
  });

  it.each([
    ["0", { count: 0 }],
    ["21", { count: 21 }],
    ["not a number", { count: "3" }],
    ["a fraction", { count: 1.5 }],
    ["missing", {}],
    ["extra keys", { count: 1, code: "LUMA-PILIHSENDIRI" }],
  ])("answers 400 for count %s", async (_, body) => {
    const { response } = await mutate("POST", "/api/invites", body);
    expect(response.status).toBe(400);
    expect(await errorCode(response)).toBe("BAD_REQUEST");
  });
});

describe("GET /api/invites", () => {
  it("filters by status and shows who used a code, in one D1 batch (+1 guard)", async () => {
    const { codes } = (await (await mutate("POST", "/api/invites", { count: 2 })).response.json()) as { codes: string[] };
    const [free, taken] = codes as [string, string];
    const user = await createUser();
    await createDb(env.DB)
      .update(inviteCodes)
      .set({ usedBy: user.id, usedAt: new Date("2026-11-10T00:00:00Z") })
      .where(eq(inviteCodes.code, normalizeInviteCode(taken)));

    const all = await call("/api/invites", { headers: { cookie: await adminCookie() } });
    expect(all.d1Queries).toBe(3);
    const unused = await list(`?status=unused&limit=50&q=${free}`);
    const used = await list(`?status=used&limit=50&q=${taken}`);
    expect(unused.map((i) => i.code)).toContain(free);
    expect(unused.map((i) => i.code)).not.toContain(taken);
    expect(used.find((i) => i.code === taken)).toEqual({
      code: taken,
      usedBy: { id: user.id, email: user.email },
      usedAt: "2026-11-10T00:00:00.000Z",
    });
    expect(used.every((i) => i.usedAt !== null)).toBe(true);
    expect(unused.every((i) => i.usedAt === null && i.usedBy === null)).toBe(true);
  });

  it("keeps a code used by a deleted account as used, with usedBy null", async () => {
    const user = await createUser();
    await giveUserData(user.id, { invite: "LUMA-HAPUSAKUN1" });
    await createDb(env.DB).update(inviteCodes).set({ usedBy: null }).where(eq(inviteCodes.code, "LUMA-HAPUSAKUN1"));
    expect((await list("?status=used&q=HAPUSAKUN1")).find((i) => i.code === "LUMA-HAPUS-AKUN1")).toMatchObject({ usedBy: null });
  });

  it("searches the code (case and dashes ignored) or the email, and counts follow the search", async () => {
    const t = tag();
    const user = await createUser({ email: `inv-${t.toLowerCase()}@luma.test` });
    await db().insert(inviteCodes).values([{ code: `LUMA-${t}AAAA` }, { code: `LUMA-${t}BBBB` }, { code: "LUMA-OTHER00000", usedBy: user.id, usedAt: new Date() }]);

    const byCode = await page(`?q=${t.toLowerCase().slice(0, 3)}-${t.toLowerCase().slice(3)}`);
    expect(byCode.items.map((i) => i.code).sort()).toEqual([`LUMA-${t.slice(0, 5)}-${t.slice(5)}AAAA`, `LUMA-${t.slice(0, 5)}-${t.slice(5)}BBBB`]);
    expect(byCode.counts).toEqual({ all: 2, unused: 2, used: 0 });

    const byEmail = await page(`?q=inv-${t.toLowerCase()}`);
    expect(byEmail.items.map((i) => i.code)).toEqual(["LUMA-OTHER-00000"]);
    expect(byEmail).toMatchObject({ total: 1, counts: { all: 1, unused: 0, used: 1 } });
  });

  it("sorts by code or date used, filters used within 7/30 days, and pages with a total", async () => {
    const t = tag();
    const now = Date.now();
    await db().insert(inviteCodes).values([
      { code: `LUMA-${t}0001` }, // unused
      { code: `LUMA-${t}0002`, usedAt: new Date(now - 2 * DAY) },
      { code: `LUMA-${t}0003`, usedAt: new Date(now - 10 * DAY) },
      { code: `LUMA-${t}0004`, usedAt: new Date(now - 40 * DAY) },
    ]);
    const codes = async (query: string) => (await list(`?q=${t}&${query}`)).map((i) => i.code.slice(-4));

    expect(await codes("sort=default")).toEqual(["0001", "0002", "0003", "0004"]);
    expect(await codes("sort=usedAt&dir=asc")).toEqual(["0004", "0003", "0002", "0001"]);
    expect(await codes("sort=usedAt&dir=desc")).toEqual(["0002", "0003", "0004", "0001"]);
    expect(await codes("sort=code&dir=desc")).toEqual(["0004", "0003", "0002", "0001"]);
    expect(await codes("usedWithin=7d")).toEqual(["0002"]);
    expect(await codes("usedWithin=30d")).toEqual(["0002", "0003"]);

    const p2 = await page(`?q=${t}&sort=code&dir=asc&limit=3&page=2`);
    expect(p2).toMatchObject({ total: 4, page: 2, pageCount: 2, counts: { all: 4, unused: 1, used: 3 } });
    expect(p2.items.map((i) => i.code.slice(-4))).toEqual(["0004"]);
    // With a status filter, `total` and that status's count share their SQL text.
    expect(await page(`?q=${t}&status=unused`)).toMatchObject({ total: 1, pageCount: 1 });
    expect(await page(`?q=${t}&status=used`)).toMatchObject({ total: 3, pageCount: 1 });
    const window = await page(`?q=${t}&usedWithin=30d`);
    expect(window).toMatchObject({ total: 2, counts: { all: 4, unused: 1, used: 3 } });
  });

  it.each(["status=semua", "usedWithin=90d", "sort=email", "dir=up", "page=0", "limit=51", `q=${"a".repeat(101)}`])("answers 400 for %s", async (query) => {
    const { response } = await call(`/api/invites?${query}`, { headers: { cookie: await adminCookie() } });
    expect(response.status).toBe(400);
  });
});

describe("DELETE /api/invites/:code", () => {
  it("deletes an unused code with 204 in one query (audit), accepting the typed format", async () => {
    const { codes } = (await (await mutate("POST", "/api/invites", { count: 1 })).response.json()) as { codes: string[] };
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const { response, d1Queries } = await mutate("DELETE", `/api/invites/${codes[0]!.toLowerCase().replaceAll("-", "")}`);
    expect(response.status).toBe(204);
    expect(d1Queries).toBe(2);
    expect(await stored(codes[0]!)).toBeNull();
    expect(log.mock.calls.map((c) => JSON.parse(c[0] as string)).find((l) => l.message === "audit")).toMatchObject({
      action: "invite.delete",
      targetId: normalizeInviteCode(codes[0]!),
    });
    log.mockRestore();
  });

  it("answers 409 for a used code and keeps it", async () => {
    const user = await createUser();
    await giveUserData(user.id, { invite: "LUMA-SUDAHDIPAKAI" });
    const { response } = await mutate("DELETE", "/api/invites/LUMA-SUDAHDIPAKAI");
    expect(response.status).toBe(409);
    expect(await errorCode(response)).toBe("INVITE_CODE_USED");
    expect(await stored("LUMA-SUDAHDIPAKAI")).not.toBeNull();
  });

  it("answers 404 for a missing code and 400 for a malformed one", async () => {
    const missing = await mutate("DELETE", "/api/invites/LUMA-GAKADA");
    expect(missing.response.status).toBe(404);
    expect(await errorCode(missing.response)).toBe("NOT_FOUND");
    expect((await mutate("DELETE", "/api/invites/LUMA%20SPASI")).response.status).toBe(400);
  });
});

describe("displayInviteCode", () => {
  it("re-adds the middle dash to new codes and leaves old short codes alone", () => {
    expect(displayInviteCode("LUMA-ABCDE23456")).toBe("LUMA-ABCDE-23456");
    expect(displayInviteCode("LUMA-7Q2K")).toBe("LUMA-7Q2K");
  });
});
