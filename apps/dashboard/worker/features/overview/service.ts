import type { Overview, OverviewUsage } from "@luma/contracts/dashboard/overview";
import type { Db } from "@luma/core/db/client";
import { log } from "@luma/worker-kit/log";
import { DAY_MS } from "@luma/core/encoding";
import { monthSpendUsd } from "./activity";
import { overviewCounts, usageOverview } from "./repo";

/** D1 free tier: rows written per day for the whole account (docs/budgets.md, Free-tier limits). */
export const D1_DAILY_WRITE_LIMIT = 100_000;

const on = (flag: string) => flag === "true";

/**
 * Overview: 1 D1 batch + 1 OpenRouter subrequest. OpenRouter failing → `spendUsd: null`
 * (logged) so the page still opens. `asOf` is the last UTC day the spend covers.
 */
export async function getOverview(
  db: Db,
  env: Env,
  requestId: string,
  now = new Date(),
): Promise<Overview> {
  const syncDay = Math.floor(now.getTime() / DAY_MS);
  const [counts, spendUsd] = await Promise.all([
    overviewCounts(db, { since: new Date(now.getTime() - 7 * DAY_MS), syncDay }),
    // No management key (local dev / e2e): skip the call instead of a guaranteed 401.
    env.OPENROUTER_MANAGEMENT_KEY
      ? monthSpendUsd(env.OPENROUTER_MANAGEMENT_KEY, env.OPENROUTER_WORKSPACE_ID, now).catch(
          (e: Error) => {
            log.error("openrouter activity failed", { request_id: requestId, error: e.message });
            return null;
          },
        )
      : null,
  ]);
  return {
    users: {
      total: counts.users.total,
      new7d: counts.users.new_since,
      banned: counts.users.banned,
    },
    storage: { r2_bytes: counts.storage.r2_bytes, sync_bytes: counts.storage.sync_bytes },
    sync_today: { rows: counts.storage.sync_rows_today, limit: D1_DAILY_WRITE_LIMIT },
    invites: { unused: counts.invites.unused },
    flags: {
      sync: on(env.SYNC_ENABLED),
      backup: on(env.BACKUP_ENABLED),
      ai_key: on(env.AI_KEY_ENABLED),
    },
    ai: {
      spend_usd: spendUsd === null ? null : Math.round(spendUsd * 1e6) / 1e6,
      budget_usd: Number(env.AI_MONTHLY_BUDGET_USD),
      as_of: new Date((syncDay - 1) * DAY_MS).toISOString().slice(0, 10),
    },
  };
}

const utcDay = (ms: number) => new Date(ms).toISOString().slice(0, 10);

/**
 * Cross-user usage for the last `days` days, today included: 1 batch, no subrequest. Days are
 * the apps' local days compared to UTC dates, so a day can sit one off at either end.
 */
export async function getUsageOverview(
  db: Db,
  days: number,
  now = Date.now(),
): Promise<OverviewUsage> {
  const to = utcDay(now);
  const span = {
    from: utcDay(now - (days - 1) * DAY_MS),
    to,
    weekFrom: utcDay(now - 6 * DAY_MS),
    monthFrom: `${to.slice(0, 7)}-01`,
  };
  const found = await usageOverview(db, span);
  return {
    from: span.from,
    to,
    totals: found.totals,
    month: { from: span.monthFrom, cost_usd: found.month.cost_usd },
    active: found.active,
    days: found.days,
    features: found.features,
    models: found.models,
    key_sources: found.keySources,
    top_users: found.topUsers,
    top_books: found.topBooks,
  };
}
