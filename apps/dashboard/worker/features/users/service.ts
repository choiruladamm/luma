import type { BanResult, UnbanResult, UserDetail, UserList } from "@luma/contracts/dashboard/users";
import type { OpenRouterAdmin } from "@luma/core/openrouter";
import type { Db } from "@luma/core/db/client";
import { log } from "@luma/worker-kit/log";
import { ApiError } from "../../lib/errors";
import {
  banUser,
  findUserDetail,
  findUserKeyHash,
  listUsers,
  type UserListQuery,
  type UserRow,
  unbanUser,
} from "./repo";

const iso = (d: Date | null) => d?.toISOString() ?? null;

const userItem = (row: UserRow) => ({
  ...row,
  created_at: row.created_at.toISOString(),
  last_active_at: row.last_active_at === null ? null : new Date(row.last_active_at).toISOString(),
  banned: Boolean(row.banned),
  has_ai_key: Boolean(row.has_ai_key),
});

/**
 * User list page, 1 batch (rows + total). Without `q` there is no relevance, so that sort falls
 * back to newest; a page past the end returns no items (the client clamps).
 */
export async function getUsers(
  db: Db,
  query: Omit<UserListQuery, "sort" | "now"> & { sort?: UserListQuery["sort"] },
): Promise<UserList> {
  const q = query.q || undefined;
  const fallback = q ? "relevance" : "created";
  const sort = query.sort === "relevance" && !q ? fallback : (query.sort ?? fallback);
  const { rows, total } = await listUsers(db, { ...query, q, sort, now: Date.now() });
  return {
    items: rows.map(userItem),
    total,
    page: query.page,
    page_count: Math.max(1, Math.ceil(total / query.limit)),
  };
}

/** Today's spend on the key, or null (logged) when OpenRouter fails. */
async function dailyUsage(openrouter: OpenRouterAdmin, keyHash: string, requestId: string) {
  try {
    return (await openrouter.getUsage(keyHash)).usageDaily;
  } catch (e) {
    log.error("openrouter getUsage failed", {
      request_id: requestId,
      error: e instanceof Error ? e.message : String(e),
    });
    return null;
  }
}

/**
 * User detail: 1 batch + 1 `getUsage` subrequest when the user has a key. If
 * OpenRouter fails → `usage_daily: null` (logged), so the detail and ban button still open.
 */
export async function getUserDetail(
  db: Db,
  openrouter: OpenRouterAdmin,
  id: string,
  requestId: string,
): Promise<UserDetail> {
  const found = await findUserDetail(db, id);
  if (!found) throw new ApiError(404, "NOT_FOUND", "User not found");
  const { key } = found;
  const ai = key && {
    limit: key.limitUsd,
    usage_daily: await dailyUsage(openrouter, key.keyHash, requestId),
    expires_at: key.expiresAt.toISOString(),
  };
  return {
    ...userItem(found.user),
    sessions: found.sessions.map((s) => ({
      ...s,
      created_at: s.created_at.toISOString(),
      updated_at: s.updated_at.toISOString(),
    })),
    ai,
    invite: found.invite ? { code: found.invite.code, used_at: iso(found.invite.used_at) } : null,
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
export async function ban(db: Db, openrouter: OpenRouterAdmin, id: string): Promise<BanResult> {
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
  return { banned: true as const, key_revoked: found.keyHash !== null };
}

/** Unban = `banned = 0`, 1 query. A new key is created lazily when the app asks again. */
export async function unban(db: Db, id: string): Promise<UnbanResult> {
  if (!(await unbanUser(db, id))) throw new ApiError(404, "NOT_FOUND", "User not found");
  return { banned: false as const };
}
