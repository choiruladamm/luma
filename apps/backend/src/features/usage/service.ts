import type { UsageBody, UsageResult } from "@luma/contracts/backend/usage";
import { DAY_MS } from "@luma/core/encoding";
import { ApiError } from "../../lib/errors";
import { usageQuota, writeUsage } from "./repo";

/**
 * Usage rows a user may write per UTC day. The app sends about one day of rows a day; this
 * leaves room for a backlog of unsent days while capping what one account can spend of the
 * shared D1 write quota (docs/budgets.md, Free-tier limits).
 */
export const USAGE_DAILY_ROWS = 2000;

/**
 * Upserts the app's daily rollup: 1 quota read, then 1 atomic batch. Days are the app's local
 * days, so a day up to one ahead of UTC (UTC+14) is accepted; anything later is rejected.
 */
export async function saveUsage(
  d1: D1Database,
  userId: string,
  body: UsageBody,
  now = new Date(),
): Promise<UsageResult> {
  const latest = new Date(now.getTime() + DAY_MS).toISOString().slice(0, 10);
  if (body.rows.some((r) => r.day > latest)) {
    throw new ApiError(400, "BAD_REQUEST", "Days must not be in the future");
  }

  const day = Math.floor(now.getTime() / DAY_MS);
  const quota = await usageQuota(d1, userId);
  const rowsToday = (quota.day === day ? quota.rows : 0) + body.rows.length;
  if (rowsToday > USAGE_DAILY_ROWS) {
    const retryAfter = Math.ceil(((day + 1) * DAY_MS - now.getTime()) / 1000);
    throw new ApiError(429, "QUOTA_EXCEEDED", "Daily usage quota reached", {
      "Retry-After": String(retryAfter),
    });
  }

  await writeUsage(d1, userId, body.rows, { day, now: now.getTime() });
  return { applied: body.rows.length };
}
