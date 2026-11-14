import type { Db } from "../../../../backend/src/db/client";
import { DAY_MS } from "../../../../backend/src/lib/encoding";
import { monthSpendUsd } from "./activity";
import { overviewCounts } from "./repo";

/** D1 free tier: rows written per day for the whole account (docs/backend.md, Aturan free tier). */
export const D1_DAILY_WRITE_LIMIT = 100_000;

const on = (flag: string) => flag === "true";

/**
 * Overview: 1 D1 batch + 1 OpenRouter subrequest. OpenRouter failing → `spendUsd: null`
 * (logged) so the page still opens. `asOf` is the last UTC day the spend covers.
 */
export async function getOverview(db: Db, env: Env, requestId: string, now = new Date()) {
  const syncDay = Math.floor(now.getTime() / DAY_MS);
  const [counts, spendUsd] = await Promise.all([
    overviewCounts(db, { since: new Date(now.getTime() - 7 * DAY_MS), syncDay }),
    monthSpendUsd(env.OPENROUTER_MANAGEMENT_KEY, env.OPENROUTER_WORKSPACE_ID, now).catch((e: Error) => {
      console.error(JSON.stringify({ message: "openrouter activity failed", requestId, error: e.message }));
      return null;
    }),
  ]);
  return {
    users: { total: counts.users.total, new7d: counts.users.newSince, banned: counts.users.banned },
    storage: { r2Bytes: counts.storage.r2Bytes, syncBytes: counts.storage.syncBytes },
    syncToday: { rows: counts.storage.syncRowsToday, limit: D1_DAILY_WRITE_LIMIT },
    invites: { unused: counts.invites.unused },
    flags: { sync: on(env.SYNC_ENABLED), backup: on(env.BACKUP_ENABLED), aiKey: on(env.AI_KEY_ENABLED) },
    ai: {
      spendUsd: spendUsd === null ? null : Math.round(spendUsd * 1e6) / 1e6,
      budgetUsd: Number(env.AI_MONTHLY_BUDGET_USD),
      asOf: new Date((syncDay - 1) * DAY_MS).toISOString().slice(0, 10),
    },
  };
}
