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
const list = async (query = "") =>
  ((await (await call(`/api/invites${query}`, { headers: { cookie: await adminCookie() } })).response.json()) as { items: Item[] })
    .items;
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
  it("filters by status and shows who used a code, in one D1 query (+1 guard)", async () => {
    const { codes } = (await (await mutate("POST", "/api/invites", { count: 2 })).response.json()) as { codes: string[] };
    const [free, taken] = codes as [string, string];
    const user = await createUser();
    await createDb(env.DB)
      .update(inviteCodes)
      .set({ usedBy: user.id, usedAt: new Date("2026-11-10T00:00:00Z") })
      .where(eq(inviteCodes.code, normalizeInviteCode(taken)));

    const all = await call("/api/invites", { headers: { cookie: await adminCookie() } });
    expect(all.d1Queries).toBe(2);
    const unused = await list("?status=unused");
    const used = await list("?status=used");
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
    expect((await list("?status=used")).find((i) => i.code === "LUMA-HAPUS-AKUN1")).toMatchObject({ usedBy: null });
  });

  it("answers 400 for an unknown status", async () => {
    const { response } = await call("/api/invites?status=semua", { headers: { cookie: await adminCookie() } });
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
