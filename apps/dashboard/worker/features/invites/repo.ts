// Every D1 query of the invites feature. Each function is one query-budget unit.
import { and, asc, count, desc, eq, gte, isNotNull, isNull, or, sql } from "drizzle-orm";
import type { Db } from "../../../../backend/src/db/client";
import { inviteCodes, users } from "../../../../backend/src/db/schema";

export type InviteListQuery = {
  status?: "unused" | "used";
  /** Only codes used within the window (so implies used). */
  usedWithin?: "7d" | "30d";
  q?: string;
  sort: "default" | "usedAt" | "code";
  dir: "asc" | "desc";
  page: number;
  limit: number;
  /** "Now" for the used-within window (ms), passed in so tests can pin it. */
  now: number;
};

const DAY_MS = 86_400_000;
const escapeLike = (q: string) => q.replace(/[\\%_]/g, (ch) => `\\${ch}`);

/**
 * 1 batch (2 statements): one page of invites (with the user who used them) and the counts.
 * `q` matches the code without dashes (codes are stored normalized: upper case) or the user's
 * email, anywhere. The counts follow `q` only (the status tabs); `total` follows every filter.
 * "Used" = `used_at` set (sign-up); `used_by` may be null after account deletion.
 */
export async function listInvites(db: Db, query: InviteListQuery) {
  const needle = query.q ? escapeLike(query.q) : undefined;
  const search = needle
    ? or(
        sql`replace(${inviteCodes.code}, '-', '') like ${`%${needle.toUpperCase().replaceAll("-", "")}%`} escape '\\'`,
        sql`${users.email} like ${`%${needle}%`} escape '\\'`,
      )
    : undefined;
  const rowFilter = and(
    query.status === "unused" ? isNull(inviteCodes.usedAt) : query.status === "used" ? isNotNull(inviteCodes.usedAt) : undefined,
    query.usedWithin ? gte(inviteCodes.usedAt, new Date(query.now - (query.usedWithin === "7d" ? 7 : 30) * DAY_MS)) : undefined,
  );

  const by = query.dir === "asc" ? asc : desc;
  const order =
    query.sort === "code"
      ? [by(inviteCodes.code)]
      : query.sort === "usedAt"
        ? // Unused codes (no date) go last both ways.
          [sql`${inviteCodes.usedAt} is null`, by(inviteCodes.usedAt), asc(inviteCodes.code)]
        : // Unused first (the ones an admin hands out), then most recently used.
          [sql`${inviteCodes.usedAt} is not null`, desc(inviteCodes.usedAt), asc(inviteCodes.code)];

  const [rows, [counts]] = await db.batch([
    db
      .select({ code: inviteCodes.code, usedAt: inviteCodes.usedAt, userId: users.id, email: users.email })
      .from(inviteCodes)
      .leftJoin(users, eq(users.id, inviteCodes.usedBy))
      .where(and(search, rowFilter))
      .orderBy(...order)
      .limit(query.limit)
      .offset((query.page - 1) * query.limit),
    db
      .select({
        all: count(),
        unused: sql<number>`coalesce(sum(${inviteCodes.usedAt} is null), 0)`.mapWith(Number),
        used: sql<number>`coalesce(sum(${inviteCodes.usedAt} is not null), 0)`.mapWith(Number),
        total: sql<number>`coalesce(sum(${rowFilter ?? sql`1`}), 0)`.mapWith(Number),
      })
      .from(inviteCodes)
      .leftJoin(users, eq(users.id, inviteCodes.usedBy))
      .where(search),
  ]);
  return { rows, counts: counts ?? { all: 0, unused: 0, used: 0, total: 0 } };
}

/** 1 insert for all codes (already normalized). */
export const insertInvites = (db: Db, codes: string[]) => db.insert(inviteCodes).values(codes.map((code) => ({ code })));

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
