// Every D1 query of the users feature. Each function is one query-budget unit.
import {
  and,
  asc,
  count,
  desc,
  eq,
  gte,
  isNotNull,
  isNull,
  lte,
  ne,
  type SQL,
  sql,
} from "drizzle-orm";
import type { Db } from "@luma/core/db/client";
import {
  accounts,
  aiKeys,
  inviteCodes,
  sessions,
  usageDaily,
  users,
  userStorage,
} from "@luma/core/db/schema";
import { USAGE_TOP_BOOKS } from "@luma/contracts/dashboard/users";
import { DAY_MS } from "@luma/core/encoding";

// Correlated subquery: uses the sessions(user_id) index. Also a filter and a sort key.
const lastActive = sql<
  number | null
>`(select max(${sessions.updatedAt}) from ${sessions} where ${sessions.userId} = ${users.id})`;
const r2Bytes = sql<number>`coalesce(${userStorage.bytes}, 0)`;
const syncBytes = sql<number>`coalesce(${userStorage.syncBytes}, 0)`;

/** User columns for list and detail, aliased to the wire keys. Picked explicitly: `key_enc` and session tokens never leave. */
const userColumns = {
  id: users.id,
  email: users.email,
  name: users.name,
  created_at: users.createdAt,
  banned: users.banned,
  last_active_at: lastActive,
  has_ai_key: sql<number>`${aiKeys.userId} is not null`,
  r2_bytes: r2Bytes,
  sync_bytes: syncBytes,
};

const userRows = (db: Db) =>
  db
    .select(userColumns)
    .from(users)
    .leftJoin(userStorage, eq(userStorage.userId, users.id))
    .leftJoin(aiKeys, eq(aiKeys.userId, users.id));

export type UserRow = Awaited<ReturnType<ReturnType<typeof userRows>["all"]>>[number];

export type UserSort = "created" | "lastActive" | "r2" | "sync" | "relevance";
export type UserListQuery = {
  q?: string;
  status?: "active" | "banned";
  ai?: "yes" | "no";
  activity?: "7d" | "30d" | "never";
  sort: UserSort;
  dir: "asc" | "desc";
  page: number;
  limit: number;
  /** "Now" for the activity windows (ms), passed in so tests can pin it. */
  now: number;
};

/**
 * Search: `q` anywhere in the email or the name, case-insensitive. Ranked: 0 exact email,
 * 1 email prefix, 2 start of a word (after . _ - @ in the email, or a word of the name),
 * 3 anywhere else. `instr` over lower-cased text instead of LIKE: D1 caps LIKE patterns at 50
 * bytes (a long query failed with "pattern too complex"), and `%`/`_` need no escaping. Same rows
 * read as LIKE: neither can use an index.
 */
const at = (text: SQL, part: string) => sql`instr(${text}, ${part})`;

function search(q: string) {
  const term = q.toLowerCase();
  const email = sql`lower(${users.email})`;
  const name = sql`lower(${users.name})`;
  const filter = sql`(${at(email, term)} > 0 or ${at(name, term)} > 0)`;
  const rank = sql<number>`case
    when ${email} = ${term} then 0
    when ${at(email, term)} = 1 then 1
    when ${at(email, `.${term}`)} > 0 or ${at(email, `_${term}`)} > 0 or ${at(email, `-${term}`)} > 0 or ${at(email, `@${term}`)} > 0 or ${at(name, term)} = 1 or ${at(name, ` ${term}`)} > 0 then 2
    else 3 end`;
  return { filter, rank };
}

function sortOrder({ sort, dir }: UserListQuery, rank: SQL | undefined): SQL[] {
  const by = dir === "asc" ? asc : desc;
  switch (sort) {
    case "relevance":
      return rank ? [rank] : [by(users.createdAt)];
    case "lastActive":
      // Never-active users go last in both directions.
      return [sql`${lastActive} ${sql.raw(dir)} nulls last`];
    case "r2":
      return [by(r2Bytes)];
    case "sync":
      return [by(syncBytes)];
    case "created":
      return [by(users.createdAt)];
  }
}

/**
 * 1 batch (2 statements): one page of users and the total for the same filters. Filters: search
 * (email or name), ban status, subsidized key, activity window. Sorted by the chosen column (ties:
 * newest, then id), relevance first when searching. Offset paging: rows skipped are still read,
 * fine at the dashboard's user counts.
 */
export async function listUsers(db: Db, query: UserListQuery) {
  const found = query.q ? search(query.q) : undefined;
  const filters: (SQL | undefined)[] = [found?.filter];
  if (query.status) filters.push(eq(users.banned, query.status === "banned"));
  if (query.ai) filters.push(query.ai === "yes" ? isNotNull(aiKeys.userId) : isNull(aiKeys.userId));
  if (query.activity === "never") filters.push(sql`${lastActive} is null`);
  else if (query.activity)
    filters.push(gte(lastActive, query.now - (query.activity === "7d" ? 7 : 30) * DAY_MS));
  const where = and(...filters);

  const by = query.dir === "asc" ? asc : desc;
  const tiebreak =
    query.sort === "created" ? [by(users.id)] : [desc(users.createdAt), desc(users.id)];

  const [rows, [total]] = await db.batch([
    userRows(db)
      .where(where)
      .orderBy(...sortOrder(query, found?.rank), ...tiebreak)
      .limit(query.limit)
      .offset((query.page - 1) * query.limit),
    db
      .select({ n: count() })
      .from(users)
      .leftJoin(aiKeys, eq(aiKeys.userId, users.id))
      .where(where),
  ]);
  return { rows, total: total?.n ?? 0 };
}

/** 1 batch (5 statements): user, sessions, AI key, invite code used, sign-in providers. */
export async function findUserDetail(db: Db, userId: string) {
  const [user, userSessions, key, invite, providers] = await db.batch([
    userRows(db).where(eq(users.id, userId)).limit(1),
    db
      .select({
        user_agent: sessions.userAgent,
        ip_address: sessions.ipAddress,
        created_at: sessions.createdAt,
        updated_at: sessions.updatedAt,
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
      .select({ code: inviteCodes.code, used_at: inviteCodes.usedAt })
      .from(inviteCodes)
      .where(eq(inviteCodes.usedBy, userId))
      .limit(1),
    db
      .select({ providerId: accounts.providerId })
      .from(accounts)
      .where(eq(accounts.userId, userId)),
  ]);
  if (!user[0]) return null;
  return {
    user: user[0],
    sessions: userSessions,
    key: key[0] ?? null,
    invite: invite[0] ?? null,
    providers: providers.map((p) => p.providerId),
  };
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
  const rows = await db
    .update(users)
    .set({ banned: false })
    .where(eq(users.id, userId))
    .returning({ id: users.id });
  return rows.length > 0;
}

// Sums over `usage_daily` rows; every raw column is aliased (see the dashboard's batch rule).
const aiSums = () => ({
  calls: sql<number>`coalesce(sum(${usageDaily.calls}), 0)`.as("calls"),
  failed: sql<number>`coalesce(sum(${usageDaily.failed}), 0)`.as("failed"),
  cost_usd: sql<number | null>`sum(${usageDaily.costUsd})`.as("cost_usd"),
});
const tokenSums = () => ({
  prompt_tokens: sql<number>`coalesce(sum(${usageDaily.promptTokens}), 0)`.as("prompt_tokens"),
  completion_tokens: sql<number>`coalesce(sum(${usageDaily.completionTokens}), 0)`.as(
    "completion_tokens",
  ),
});

/**
 * 1 batch (6 statements): user exists, totals, and the AI rows per feature, model, and key source,
 * plus the top books, over the days `from`..`to` (`YYYY-MM-DD`). Every statement reads only this
 * user's rows through the `usage_daily` primary key (user_id, day, …).
 */
export async function findUserUsage(db: Db, userId: string, from: string, to: string) {
  const range = and(
    eq(usageDaily.userId, userId),
    gte(usageDaily.day, from),
    lte(usageDaily.day, to),
  );
  const aiRange = and(range, ne(usageDaily.feature, "reading"));
  const [user, totals, features, models, keySources, books] = await db.batch([
    db.select({ id: users.id }).from(users).where(eq(users.id, userId)).limit(1),
    db
      .select({
        ...aiSums(),
        ...tokenSums(),
        reading_seconds: sql<number>`coalesce(sum(${usageDaily.readingSeconds}), 0)`.as(
          "reading_seconds",
        ),
        active_days: sql<number>`count(distinct ${usageDaily.day})`.as("active_days"),
        last_day: sql<
          string | null
        >`(select max(${usageDaily.day}) from ${usageDaily} where ${usageDaily.userId} = ${userId})`.as(
          "last_day",
        ),
      })
      .from(usageDaily)
      .where(range),
    db
      .select({ feature: usageDaily.feature, ...aiSums(), ...tokenSums() })
      .from(usageDaily)
      .where(aiRange)
      .groupBy(usageDaily.feature)
      .orderBy(sql`calls desc`),
    db
      .select({ model: usageDaily.model, ...aiSums() })
      .from(usageDaily)
      .where(aiRange)
      .groupBy(usageDaily.model)
      .orderBy(sql`calls desc`),
    db
      .select({ key_source: usageDaily.keySource, ...aiSums() })
      .from(usageDaily)
      .where(aiRange)
      .groupBy(usageDaily.keySource)
      .orderBy(sql`calls desc`),
    db
      .select({
        book_key: usageDaily.bookKey,
        // ponytail: a book renamed within the range shows one of its titles (max), not the latest.
        book_title: sql<string | null>`max(${usageDaily.bookTitle})`.as("book_title"),
        reading_seconds: sql<number>`coalesce(sum(${usageDaily.readingSeconds}), 0)`.as(
          "reading_seconds",
        ),
        ...aiSums(),
      })
      .from(usageDaily)
      .where(range)
      .groupBy(usageDaily.bookKey)
      .orderBy(sql`reading_seconds desc`, sql`calls desc`)
      .limit(USAGE_TOP_BOOKS),
  ]);
  if (!user[0]) return null;
  return { totals: totals[0]!, features, models, keySources, books };
}
