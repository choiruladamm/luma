// Every D1 query of the overview feature. Each function is one query-budget unit.
import { and, count, eq, gte, isNull, lte, ne, sql } from "drizzle-orm";
import type { Db } from "@luma/core/db/client";
import { OVERVIEW_TOP } from "@luma/contracts/dashboard/overview";
import { inviteCodes, usageDaily, users, userStorage } from "@luma/core/db/schema";

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

// Sums over `usage_daily`; every raw column is aliased (see the dashboard's batch rule).
const sums = () => ({
  calls: sql<number>`coalesce(sum(${usageDaily.calls}), 0)`.as("calls"),
  failed: sql<number>`coalesce(sum(${usageDaily.failed}), 0)`.as("failed"),
  cost_usd: sql<number | null>`sum(${usageDaily.costUsd})`.as("cost_usd"),
});
const activeUsers = () => sql<number>`count(distinct ${usageDaily.userId})`.as("active_users");

export type UsageDays = { from: string; to: string; weekFrom: string; monthFrom: string };

/**
 * 1 batch (9 statements) over every user's `usage_daily` rows in `from`..`to`, through the
 * `usage_daily_day` index: totals, month-to-date cost, daily and weekly actives, per day, per
 * feature, model, and key source, top users by cost, and top books by reading time.
 */
export async function usageOverview(db: Db, d: UsageDays) {
  const range = and(gte(usageDaily.day, d.from), lte(usageDaily.day, d.to));
  const aiRange = and(range, ne(usageDaily.feature, "reading"));
  const [totals, month, active, days, features, models, keySources, topUsers, topBooks] =
    await db.batch([
      db
        .select({
          ...sums(),
          reading_seconds: sql<number>`coalesce(sum(${usageDaily.readingSeconds}), 0)`.as(
            "reading_seconds",
          ),
          active_users: activeUsers(),
        })
        .from(usageDaily)
        .where(range),
      db
        .select({ cost_usd: sql<number | null>`sum(${usageDaily.costUsd})`.as("cost_usd") })
        .from(usageDaily)
        .where(and(gte(usageDaily.day, d.monthFrom), lte(usageDaily.day, d.to))),
      db
        .select({
          day: sql<number>`count(distinct case when ${usageDaily.day} = ${d.to} then ${usageDaily.userId} end)`.as(
            "day",
          ),
          week: activeUsers(),
        })
        .from(usageDaily)
        .where(and(gte(usageDaily.day, d.weekFrom), lte(usageDaily.day, d.to))),
      db
        .select({ day: usageDaily.day, ...sums(), active_users: activeUsers() })
        .from(usageDaily)
        .where(range)
        .groupBy(usageDaily.day)
        .orderBy(usageDaily.day),
      db
        .select({ feature: usageDaily.feature, ...sums() })
        .from(usageDaily)
        .where(aiRange)
        .groupBy(usageDaily.feature)
        .orderBy(sql`calls desc`),
      db
        .select({ model: usageDaily.model, ...sums() })
        .from(usageDaily)
        .where(aiRange)
        .groupBy(usageDaily.model)
        .orderBy(sql`calls desc`),
      db
        .select({ key_source: usageDaily.keySource, ...sums() })
        .from(usageDaily)
        .where(aiRange)
        .groupBy(usageDaily.keySource)
        .orderBy(sql`calls desc`),
      db
        .select({ id: users.id, email: users.email, name: users.name, ...sums() })
        .from(usageDaily)
        .innerJoin(users, eq(users.id, usageDaily.userId))
        .where(aiRange)
        .groupBy(users.id)
        .orderBy(sql`coalesce(sum(${usageDaily.costUsd}), 0) desc`, sql`calls desc`)
        .limit(OVERVIEW_TOP),
      db
        .select({
          // ponytail: a book with several titles across users shows one of them (max).
          book_title: sql<string | null>`max(${usageDaily.bookTitle})`.as("book_title"),
          readers: sql<number>`count(distinct ${usageDaily.userId})`.as("readers"),
          reading_seconds: sql<number>`coalesce(sum(${usageDaily.readingSeconds}), 0)`.as(
            "reading_seconds",
          ),
        })
        .from(usageDaily)
        .where(and(range, ne(usageDaily.bookKey, "")))
        .groupBy(usageDaily.bookKey)
        .orderBy(sql`reading_seconds desc`, sql`readers desc`)
        .limit(OVERVIEW_TOP),
    ]);
  return {
    totals: totals[0]!,
    month: month[0]!,
    active: active[0]!,
    days,
    features,
    models,
    keySources,
    topUsers,
    topBooks,
  };
}
