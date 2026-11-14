import type { OpenRouterAdmin } from "../../../../backend/src/clients/openrouter";
import type { Db } from "../../../../backend/src/db/client";
import { ApiError } from "../../lib/errors";
import { banUser, findUserDetail, findUserKeyHash, listUsers, type UserCursor, type UserRow, unbanUser } from "./repo";

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

/** User list, 1 query. */
export async function getUsers(db: Db, query: { q?: string; cursor?: UserCursor; limit: number }) {
  const rows = await listUsers(db, { q: query.q || undefined, cursor: query.cursor, limit: query.limit });
  const page = rows.slice(0, query.limit);
  const last = page.at(-1);
  return { items: page.map(userItem), nextCursor: rows.length > query.limit && last ? encodeCursor(last) : null };
}

/**
 * User detail: 1 batch + 1 `getUsage` subrequest when the user has a key. If
 * OpenRouter fails → `usageDaily: null` (logged), so the detail and ban button still open.
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
 * Ban = revoke subsidized AI (same as `make backend-ban`): the OpenRouter key is
 * deleted first so an extracted key dies immediately; on failure → 502 without
 * touching D1, so the ban can be retried. Idempotent.
 * D1: 1 query + 1 batch. Subrequests: 1 when the user has a key.
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
  // ponytail: if the app creates a new key between deleteKey and this batch, that key is
  // orphaned until it expires (at most the daily limit). Same as ban.ts; add a per-user lock if it happens.
  await banUser(db, id);
  return { banned: true as const, keyRevoked: found.keyHash !== null };
}

/** Unban = `banned = 0`, 1 query. A new key is created lazily when the app asks again. */
export async function unban(db: Db, id: string) {
  if (!(await unbanUser(db, id))) throw new ApiError(404, "NOT_FOUND", "User not found");
  return { banned: false as const };
}
