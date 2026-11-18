import type { OpenRouterAdmin } from "../../../../backend/src/clients/openrouter";
import type { Db } from "../../../../backend/src/db/client";
import { ApiError } from "../../lib/errors";
import { banUser, findUserDetail, findUserKeyHash, listUsers, type UserListQuery, type UserRow, unbanUser } from "./repo";

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

/**
 * User list page, 1 batch (rows + total). Without `q` there is no relevance, so that sort falls
 * back to newest; a page past the end returns no items (the client clamps).
 */
export async function getUsers(db: Db, query: Omit<UserListQuery, "sort" | "now"> & { sort?: UserListQuery["sort"] }) {
  const q = query.q || undefined;
  const sort = query.sort && (query.sort !== "relevance" || q) ? query.sort : q ? "relevance" : "created";
  const { rows, total } = await listUsers(db, { ...query, q, sort, now: Date.now() });
  return { items: rows.map(userItem), total, page: query.page, pageCount: Math.max(1, Math.ceil(total / query.limit)) };
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
    /** Better Auth provider ids ("google", "credential" for email/password). */
    providers: found.providers,
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
  // orphaned until it expires (at most the daily limit). Same as the backend's scripts/ban.ts; add a per-user lock if it happens.
  await banUser(db, id);
  return { banned: true as const, keyRevoked: found.keyHash !== null };
}

/** Unban = `banned = 0`, 1 query. A new key is created lazily when the app asks again. */
export async function unban(db: Db, id: string) {
  if (!(await unbanUser(db, id))) throw new ApiError(404, "NOT_FOUND", "User not found");
  return { banned: false as const };
}
