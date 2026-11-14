import { Hono } from "hono";
import { z } from "zod";
import { type OpenRouterAdmin, openRouterAdmin } from "../../backend/src/clients/openrouter";
import type { Db } from "../../backend/src/db/client";
import { audit } from "./audit";
import type { AppEnv } from "./env";
import { ApiError } from "./errors";
import { validate } from "./middleware";
import { banUser, findUserDetail, findUserKeyHash, listUsers, type UserRow, unbanUser } from "./repo";

export const USERS_PAGE_SIZE = 50;

const iso = (d: Date | null) => d?.toISOString() ?? null;

const userItem = (row: UserRow) => ({
  id: row.id,
  email: row.email,
  name: row.name,
  createdAt: row.createdAt.toISOString(),
  lastActiveAt: row.lastActiveAt === null ? null : new Date(row.lastActiveAt).toISOString(),
  banned: Boolean(row.banned),
  hasAiKey: Boolean(row.hasAiKey),
  r2Bytes: row.r2Bytes,
  syncBytes: row.syncBytes,
});

const encodeCursor = (row: UserRow) => `${row.createdAt.getTime()},${row.id}`;

const userId = z.string().regex(/^[A-Za-z0-9_-]{1,64}$/, "Invalid user id");

const listQuery = z.object({
  q: z.string().trim().max(100).optional(),
  cursor: z
    .string()
    .regex(/^\d{1,15},[A-Za-z0-9_-]{1,64}$/, "Invalid cursor")
    .transform((v) => {
      const [ms, id] = v.split(",") as [string, string];
      return { createdAt: new Date(Number(ms)), id };
    })
    .optional(),
  limit: z.coerce.number().int().min(1).max(USERS_PAGE_SIZE).default(USERS_PAGE_SIZE),
});

/** Daftar user, 1 query. */
export async function getUsers(db: Db, query: z.infer<typeof listQuery>) {
  const rows = await listUsers(db, { q: query.q || undefined, cursor: query.cursor, limit: query.limit });
  const page = rows.slice(0, query.limit);
  const last = page.at(-1);
  return { items: page.map(userItem), nextCursor: rows.length > query.limit && last ? encodeCursor(last) : null };
}

/**
 * Detail user: 1 batch + 1 subrequest `getUsage` kalau punya key. OpenRouter
 * gagal → `usageDaily: null` (di-log), supaya detail dan tombol ban tetap bisa dibuka.
 */
export async function getUserDetail(db: Db, openrouter: OpenRouterAdmin, id: string, requestId: string) {
  const found = await findUserDetail(db, id);
  if (!found) throw new ApiError(404, "NOT_FOUND", "User not found");
  let ai = null;
  if (found.key) {
    let usageDaily: number | null = null;
    try {
      usageDaily = (await openrouter.getUsage(found.key.keyHash)).usageDaily;
    } catch (e) {
      console.error(JSON.stringify({ message: "openrouter getUsage failed", requestId, error: (e as Error).message }));
    }
    ai = { limit: found.key.limitUsd, usageDaily, expiresAt: found.key.expiresAt.toISOString() };
  }
  return {
    ...userItem(found.user),
    sessions: found.sessions.map((s) => ({
      userAgent: s.userAgent,
      ipAddress: s.ipAddress,
      createdAt: s.createdAt.toISOString(),
      updatedAt: s.updatedAt.toISOString(),
    })),
    ai,
    invite: found.invite ? { code: found.invite.code, usedAt: iso(found.invite.usedAt) } : null,
  };
}

/**
 * Ban = cabut AI subsidi (sama dengan `make backend-ban`): key OpenRouter dihapus
 * duluan supaya key yang udah diekstrak langsung mati; gagal → 502 tanpa
 * menyentuh D1, jadi ban bisa diulang. Idempoten.
 * D1: 1 query + 1 batch. Subrequest: 1 kalau punya key.
 */
export async function ban(db: Db, openrouter: OpenRouterAdmin, id: string) {
  const found = await findUserKeyHash(db, id);
  if (!found) throw new ApiError(404, "NOT_FOUND", "User not found");
  if (found.keyHash) {
    try {
      await openrouter.deleteKey(found.keyHash);
    } catch {
      throw new ApiError(502, "OPENROUTER_FAILED", "Could not revoke the OpenRouter key");
    }
  }
  // ponytail: kalau app bikin key baru di antara deleteKey dan batch ini, key itu yatim
  // sampai kedaluwarsa (maks limit harian). Sama dengan ban.ts; kunci per user kalau kejadian.
  await banUser(db, id);
  return { banned: true as const, keyRevoked: found.keyHash !== null };
}

export const users = new Hono<AppEnv>()
  .get("/", validate("query", listQuery), async (c) => c.json(await getUsers(c.var.db, c.req.valid("query"))))
  .get("/:id", validate("param", z.object({ id: userId })), async (c) => {
    const openrouter = openRouterAdmin(c.env.OPENROUTER_MANAGEMENT_KEY);
    return c.json(await getUserDetail(c.var.db, openrouter, c.req.valid("param").id, c.var.requestId));
  })
  .post("/:id/ban", validate("param", z.object({ id: userId })), async (c) => {
    const { id } = c.req.valid("param");
    const result = await ban(c.var.db, openRouterAdmin(c.env.OPENROUTER_MANAGEMENT_KEY), id);
    audit(c, "user.ban", id);
    return c.json(result);
  })
  .post("/:id/unban", validate("param", z.object({ id: userId })), async (c) => {
    const { id } = c.req.valid("param");
    if (!(await unbanUser(c.var.db, id))) throw new ApiError(404, "NOT_FOUND", "User not found");
    audit(c, "user.unban", id);
    return c.json({ banned: false as const });
  });
