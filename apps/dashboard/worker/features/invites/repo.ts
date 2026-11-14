// Every D1 query of the invites feature. Each function is one query-budget unit.
import { and, asc, desc, eq, isNotNull, isNull } from "drizzle-orm";
import type { Db } from "../../../../backend/src/db/client";
import { inviteCodes, users } from "../../../../backend/src/db/schema";

// ponytail: no pagination; fine while invites are beta-sized. Add a cursor when a list nears this cap.
export const INVITES_MAX = 500;

/** 1 query: invites with the user who used them. "Used" = `used_at` set (sign-up), `used_by` may be null after account deletion. */
export function listInvites(db: Db, status?: "unused" | "used") {
  const query = db
    .select({ code: inviteCodes.code, usedAt: inviteCodes.usedAt, userId: users.id, email: users.email })
    .from(inviteCodes)
    .leftJoin(users, eq(users.id, inviteCodes.usedBy));
  const filtered =
    status === "unused"
      ? query.where(isNull(inviteCodes.usedAt))
      : status === "used"
        ? query.where(isNotNull(inviteCodes.usedAt))
        : query;
  return filtered.orderBy(desc(inviteCodes.usedAt), asc(inviteCodes.code)).limit(INVITES_MAX);
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
