// Every D1 query of the users feature. Each function is one query-budget unit.
import { and, desc, eq, lt, or, type SQL, sql } from "drizzle-orm";
import type { Db } from "../../../../backend/src/db/client";
import { aiKeys, inviteCodes, sessions, users, userStorage } from "../../../../backend/src/db/schema";

/** User columns for list and detail. Picked explicitly: `key_enc` and session tokens never leave. */
const userColumns = {
  id: users.id,
  email: users.email,
  name: users.name,
  createdAt: users.createdAt,
  banned: users.banned,
  // Correlated subquery: uses the sessions(user_id) index, only for returned rows.
  lastActiveAt: sql<number | null>`(select max(${sessions.updatedAt}) from ${sessions} where ${sessions.userId} = ${users.id})`,
  hasAiKey: sql<number>`${aiKeys.userId} is not null`,
  r2Bytes: sql<number>`coalesce(${userStorage.bytes}, 0)`,
  syncBytes: sql<number>`coalesce(${userStorage.syncBytes}, 0)`,
};

const userRows = (db: Db) =>
  db
    .select(userColumns)
    .from(users)
    .leftJoin(userStorage, eq(userStorage.userId, users.id))
    .leftJoin(aiKeys, eq(aiKeys.userId, users.id));

export type UserRow = Awaited<ReturnType<ReturnType<typeof userRows>["all"]>>[number];
export type UserCursor = { createdAt: Date; id: string };

/** Escape `%`, `_`, `\` so `q` only matches as a literal prefix. */
export const likePrefix = (q: string) => `${q.replace(/[\\%_]/g, (ch) => `\\${ch}`)}%`;

/** 1 query: newest first, cursor (createdAt, id). Fetches `limit + 1` to know if there is a next page. */
export function listUsers(db: Db, { q, cursor, limit }: { q?: string; cursor?: UserCursor; limit: number }) {
  const filters: SQL[] = [];
  if (q) filters.push(sql`${users.email} like ${likePrefix(q)} escape '\\'`);
  if (cursor) {
    filters.push(
      or(lt(users.createdAt, cursor.createdAt), and(eq(users.createdAt, cursor.createdAt), lt(users.id, cursor.id)))!,
    );
  }
  return userRows(db)
    .where(and(...filters))
    .orderBy(desc(users.createdAt), desc(users.id))
    .limit(limit + 1);
}

/** 1 batch (4 statements): user, sessions, AI key, invite code used. */
export async function findUserDetail(db: Db, userId: string) {
  const [user, userSessions, key, invite] = await db.batch([
    userRows(db).where(eq(users.id, userId)).limit(1),
    db
      .select({
        userAgent: sessions.userAgent,
        ipAddress: sessions.ipAddress,
        createdAt: sessions.createdAt,
        updatedAt: sessions.updatedAt,
      })
      .from(sessions)
      .where(eq(sessions.userId, userId))
      .orderBy(desc(sessions.updatedAt))
      .limit(50),
    db
      .select({ keyHash: aiKeys.keyHash, limitUsd: aiKeys.limitUsd, expiresAt: aiKeys.expiresAt })
      .from(aiKeys)
      .where(eq(aiKeys.userId, userId))
      .limit(1),
    db
      .select({ code: inviteCodes.code, usedAt: inviteCodes.usedAt })
      .from(inviteCodes)
      .where(eq(inviteCodes.usedBy, userId))
      .limit(1),
  ]);
  if (!user[0]) return null;
  return { user: user[0], sessions: userSessions, key: key[0] ?? null, invite: invite[0] ?? null };
}

/** 1 query: does the user exist + AI key hash (null when there is none). */
export async function findUserKeyHash(db: Db, userId: string) {
  const [row] = await db
    .select({ id: users.id, keyHash: aiKeys.keyHash })
    .from(users)
    .leftJoin(aiKeys, eq(aiKeys.userId, users.id))
    .where(eq(users.id, userId))
    .limit(1);
  return row ?? null;
}

/** 1 batch: `banned = 1` + delete the `ai_keys` row (same as `make backend-ban`). */
export const banUser = (db: Db, userId: string) =>
  db.batch([
    db.update(users).set({ banned: true }).where(eq(users.id, userId)),
    db.delete(aiKeys).where(eq(aiKeys.userId, userId)),
  ]);

/** 1 query: `banned = 0`. False when the user doesn't exist. */
export async function unbanUser(db: Db, userId: string) {
  const rows = await db.update(users).set({ banned: false }).where(eq(users.id, userId)).returning({ id: users.id });
  return rows.length > 0;
}
