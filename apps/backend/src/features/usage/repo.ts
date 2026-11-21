// Queries for `usage_daily` + the usage quota in `user_storage` (docs/backend.md, Usage analytics).
// Raw SQL, not Drizzle, for the same reason as sync/repo.ts: 500 rows of 13 columns only fit
// D1's 100 bound parameters per query as one `json_each` parameter.
import type { UsageRow } from "@luma/contracts/backend/usage";

export type UsageQuota = { day: number; rows: number };

/** 1 query: usage rows written on UTC day `day` (both 0 before the first send). */
export async function usageQuota(d1: D1Database, userId: string): Promise<UsageQuota> {
  const row = await d1
    .prepare("SELECT usage_day AS day, usage_rows AS rows FROM user_storage WHERE user_id = ?1")
    .bind(userId)
    .first<UsageQuota>();
  return row ?? { day: 0, rows: 0 };
}

/**
 * 1 atomic `db.batch()` (2 statements): counts the rows against the quota of UTC day `day`
 * (reset when the day changes), then upserts every row. A row that exists is replaced, not
 * added to, so a resent day keeps its counts; a key repeated in one batch keeps its last row.
 */
export async function writeUsage(
  d1: D1Database,
  userId: string,
  rows: UsageRow[],
  at: { day: number; now: number },
) {
  await d1.batch([
    d1
      .prepare(
        `INSERT INTO user_storage (user_id, usage_day, usage_rows) VALUES (?1, ?2, ?3)
         ON CONFLICT (user_id) DO UPDATE SET
           usage_rows = CASE WHEN usage_day = ?2 THEN usage_rows + ?3 ELSE ?3 END, usage_day = ?2`,
      )
      .bind(userId, at.day, rows.length),
    d1
      .prepare(
        `INSERT INTO usage_daily (user_id, day, feature, model, book_key, book_title, key_source,
           calls, failed, prompt_tokens, completion_tokens, cost_usd, reading_seconds, updated_at)
         SELECT ?1, json_extract(value, '$.day'), json_extract(value, '$.feature'),
           json_extract(value, '$.model'), json_extract(value, '$.book_key'),
           json_extract(value, '$.book_title'), json_extract(value, '$.key_source'),
           json_extract(value, '$.calls'), json_extract(value, '$.failed'),
           json_extract(value, '$.prompt_tokens'), json_extract(value, '$.completion_tokens'),
           json_extract(value, '$.cost_usd'), json_extract(value, '$.reading_seconds'), ?2
         FROM json_each(?3) WHERE true
         ON CONFLICT (user_id, day, feature, model, book_key, key_source) DO UPDATE SET
           book_title = excluded.book_title, calls = excluded.calls, failed = excluded.failed,
           prompt_tokens = excluded.prompt_tokens, completion_tokens = excluded.completion_tokens,
           cost_usd = excluded.cost_usd, reading_seconds = excluded.reading_seconds,
           updated_at = excluded.updated_at`,
      )
      .bind(userId, at.now, JSON.stringify(rows)),
  ]);
}
