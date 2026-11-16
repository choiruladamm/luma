// Every D1 query of the invites feature. Each function is one query-budget unit.
import { and, asc, count, desc, eq, gte, isNotNull, isNull, or, sql } from "drizzle-orm";
import type { Db } from "../../../../backend/src/db/client";
import { inviteCodes, users } from "../../../../backend/src/db/schema";

export type InviteListQuery = {
  status?: "unused" | "used";
  /** Only codes used within the window (so implies used). */
  usedWithin?: "7d" | "30d";
  q?: string;
  sort: "default" | "usedAt" | "createdAt" | "code";
  dir: "asc" | "desc";
  page: number;
  limit: number;
  /** "Now" for the used-within window (ms), passed in so tests can pin it. */
  now: number;
};

const DAY_MS = 86_400_000;

/**
 * 1 batch (2 statements): one page of invites (with the user who used them) and the counts.
 * `q` matches the code without dashes (codes are stored normalized: upper case) or the user's
 * email, anywhere (case-insensitive). The counts follow `q` only (the status tabs); `total` follows every filter.
 * "Used" = `used_at` set (sign-up); `used_by` may be null after account deletion.
 */
export async function listInvites(db: Db, query: InviteListQuery) {
  // `instr`, not LIKE: D1 caps LIKE patterns at 50 bytes, and the code/email text needs no escaping.
  const search = query.q
    ? or(
        sql`instr(replace(${inviteCodes.code}, '-', ''), ${query.q.toUpperCase().replaceAll("-", "")}) > 0`,
        sql`instr(lower(${users.email}), ${query.q.toLowerCase()}) > 0`,
      )
    : undefined;
  const rowFilter = and(
    query.status === "unused" ? isNull(inviteCodes.usedAt) : query.status === "used" ? isNotNull(inviteCodes.usedAt) : undefined,
    query.usedWithin ? gte(inviteCodes.usedAt, new Date(query.now - (query.usedWithin === "7d" ? 7 : 30) * DAY_MS)) : undefined,
  );

  const by = query.dir === "asc" ? asc : desc;
  // Codes made before `created_at` existed have no date: they go last both ways.
  // ponytail: no index on used_at/created_at; invite codes stay in the hundreds. Add one if that changes.
  const newestFirst = [sql`${inviteCodes.createdAt} is null`, desc(inviteCodes.createdAt)];
  const order =
    query.sort === "code"
      ? [by(inviteCodes.code)]
      : query.sort === "usedAt"
        ? // Unused codes (no date) go last both ways.
          [sql`${inviteCodes.usedAt} is null`, by(inviteCodes.usedAt), asc(inviteCodes.code)]
        : query.sort === "createdAt"
          ? [sql`${inviteCodes.createdAt} is null`, by(inviteCodes.createdAt), asc(inviteCodes.code)]
          : // Unused first (the ones an admin hands out), newest made first; then most recently used.
            [sql`${inviteCodes.usedAt} is not null`, desc(inviteCodes.usedAt), ...newestFirst, asc(inviteCodes.code)];

  const [rows, [counts]] = await db.batch([
    db
      .select({ code: inviteCodes.code, createdAt: inviteCodes.createdAt, usedAt: inviteCodes.usedAt, userId: users.id, email: users.email })
      .from(inviteCodes)
      .leftJoin(users, eq(users.id, inviteCodes.usedBy))
      .where(and(search, rowFilter))
      .orderBy(...order)
      .limit(query.limit)
      .offset((query.page - 1) * query.limit),
    db
      // Explicit aliases: D1 names raw columns by their SQL text, and with a status filter
      // `total` has the same text as `unused`/`used`, so one would overwrite the other.
      .select({
        all: count().as("all"),
        unused: sql<number>`coalesce(sum(${inviteCodes.usedAt} is null), 0)`.mapWith(Number).as("unused"),
        used: sql<number>`coalesce(sum(${inviteCodes.usedAt} is not null), 0)`.mapWith(Number).as("used"),
        total: sql<number>`coalesce(sum(${rowFilter ?? sql`1`}), 0)`.mapWith(Number).as("total"),
      })
      .from(inviteCodes)
      .leftJoin(users, eq(users.id, inviteCodes.usedBy))
      .where(search),
  ]);
  return { rows, counts: counts ?? { all: 0, unused: 0, used: 0, total: 0 } };
}

/** 1 insert for all codes (already normalized), all with the same `createdAt`. */
export const insertInvites = (db: Db, codes: string[], createdAt: Date) => db.insert(inviteCodes).values(codes.map((code) => ({ code, createdAt })));

/** 1 query: delete only while unused. Returns whether a row was deleted. */
export async function deleteUnusedInvite(db: Db, code: string) {
  const rows = await db
    .delete(inviteCodes)
    .where(and(eq(inviteCodes.code, code), isNull(inviteCodes.usedAt)))
    .returning({ code: inviteCodes.code });
  return rows.length > 0;
}

/** 1 query: does the code exist (to tell 404 from 409 after a failed delete). */
export async function inviteExists(db: Db, code: string) {
  const [row] = await db.select({ code: inviteCodes.code }).from(inviteCodes).where(eq(inviteCodes.code, code)).limit(1);
  return row !== undefined;
}
