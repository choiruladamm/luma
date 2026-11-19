// Every D1 query of the overview feature. Each function is one query-budget unit.
import { count, isNull, sql } from "drizzle-orm";
import type { Db } from "@luma/core/db/client";
import { inviteCodes, users, userStorage } from "@luma/core/db/schema";

/**
 * 1 batch (3 aggregate statements): users (total, new since `since`, banned),
 * storage + sync rows written on UTC day `syncDay`, unused invites.
 */
export async function overviewCounts(db: Db, { since, syncDay }: { since: Date; syncDay: number }) {
  const [userRows, storageRows, inviteRows] = await db.batch([
    db
      .select({
        total: count(),
        new_since: sql<number>`coalesce(sum(${users.createdAt} >= ${since.getTime()}), 0)`,
        banned: sql<number>`coalesce(sum(${users.banned} = 1), 0)`,
      })
      .from(users),
    db
      .select({
        r2_bytes: sql<number>`coalesce(sum(${userStorage.bytes}), 0)`,
        sync_bytes: sql<number>`coalesce(sum(${userStorage.syncBytes}), 0)`,
        sync_rows_today: sql<number>`coalesce(sum(case when ${userStorage.syncDay} = ${syncDay} then ${userStorage.syncRows} else 0 end), 0)`,
      })
      .from(userStorage),
    db.select({ unused: count() }).from(inviteCodes).where(isNull(inviteCodes.usedAt)),
  ]);
  return { users: userRows[0]!, storage: storageRows[0]!, invites: inviteRows[0]! };
}
