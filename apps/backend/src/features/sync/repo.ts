// Queries for `records` + `user_storage.seq` (docs/sync-protocol.md, Push and pull).
// Raw SQL, not Drizzle, on purpose: the D1 free limits (50 queries + 100
// parameters per request) force a 500-record batch through `json_each` in
// a single statement. Each function = one query-budget unit (see its comment).
import type { Data, Kind, SyncRecord } from "./merge";

type Row = {
  kind: Kind;
  key: string;
  data: string | null;
  updated_at: number;
  deleted: number;
  schema_version: number;
};

const fromRow = (r: Row): SyncRecord => ({
  kind: r.kind,
  key: r.key,
  data: r.data == null ? null : (JSON.parse(r.data) as Data),
  updatedAt: r.updated_at,
  deleted: r.deleted === 1,
  schemaVersion: r.schema_version,
});

/** A record in D1 + its size (key length + JSON data, the `sync_bytes` quota formula). */
export type StoredRecord = SyncRecord & { size: number };

/** 1 query: existing records for the `(kind, key)` pairs in the batch. */
export async function findRecords(
  d1: D1Database,
  userId: string,
  ids: [Kind, string][],
): Promise<StoredRecord[]> {
  const { results } = await d1
    .prepare(
      `SELECT kind, key, data, updated_at, deleted, schema_version,
         length(key) + coalesce(length(data), 0) AS size FROM records
       WHERE user_id = ?1 AND (kind, key) IN
         (SELECT json_extract(value, '$[0]'), json_extract(value, '$[1]') FROM json_each(?2))`,
    )
    .bind(userId, JSON.stringify(ids))
    .all<Row & { size: number }>();
  return results.map((r) => ({ ...fromRow(r), size: r.size }));
}

export type SyncUsage = { seq: number; bytes: number; day: number; rows: number };

/** 1 query: `seq` + the user's current sync quota usage (all 0 if never pushed). */
export async function syncUsage(d1: D1Database, userId: string): Promise<SyncUsage> {
  const row = await d1
    .prepare(
      "SELECT seq, sync_bytes AS bytes, sync_day AS day, sync_rows AS rows FROM user_storage WHERE user_id = ?1",
    )
    .bind(userId)
    .first<SyncUsage>();
  return row ?? { seq: 0, bytes: 0, day: 0, rows: 0 };
}

/**
 * 1 atomic `db.batch()` (2 statements): `seq += n` + quota (`sync_bytes +=
 * [bytesDelta]`, `sync_rows += n` on UTC day [day], reset when the day changes) +
 * one `INSERT … SELECT FROM json_each` that gives each record a new sequential
 * `seq`. Returns the last `seq`.
 */
export async function writeRecords(
  d1: D1Database,
  userId: string,
  records: SyncRecord[],
  quota: { bytesDelta: number; day: number },
) {
  const n = records.length;
  const [bump] = await d1.batch<{ seq: number }>([
    d1
      .prepare(
        `INSERT INTO user_storage (user_id, seq, sync_bytes, sync_day, sync_rows) VALUES (?1, ?2, max(0, ?3), ?4, ?2)
         ON CONFLICT (user_id) DO UPDATE SET seq = seq + ?2, sync_bytes = max(0, sync_bytes + ?3),
           sync_rows = CASE WHEN sync_day = ?4 THEN sync_rows + ?2 ELSE ?2 END, sync_day = ?4
         RETURNING seq`,
      )
      .bind(userId, n, quota.bytesDelta, quota.day),
    d1
      .prepare(
        `INSERT INTO records (user_id, kind, key, data, updated_at, deleted, schema_version, seq)
         SELECT ?1, json_extract(value, '$.kind'), json_extract(value, '$.key'),
           json_extract(value, '$.data'), json_extract(value, '$.updatedAt'),
           json_extract(value, '$.deleted'), json_extract(value, '$.schemaVersion'),
           (SELECT seq FROM user_storage WHERE user_id = ?1) - ?2 + key + 1
         FROM json_each(?3) WHERE true
         ON CONFLICT (user_id, kind, key) DO UPDATE SET
           data = excluded.data, updated_at = excluded.updated_at, deleted = excluded.deleted,
           schema_version = excluded.schema_version, seq = excluded.seq`,
      )
      .bind(userId, n, JSON.stringify(records)),
  ]);
  return bump!.results[0]!.seq;
}

/**
 * 1 query through the `records_user_seq` index: records with `seq` > [since], already
 * built into JSON in SQL (`data` is already JSON), so the Worker doesn't need to
 * `JSON.parse` 500 records (10ms CPU limit). Takes [limit] rows.
 */
export async function pullRows(d1: D1Database, userId: string, since: number, limit: number) {
  const { results } = await d1
    .prepare(
      `SELECT seq, json_object(
         'kind', kind, 'key', key,
         'updatedAt', strftime('%Y-%m-%dT%H:%M:%fZ', updated_at / 1000.0, 'unixepoch'),
         'deleted', json(CASE WHEN deleted THEN 'true' ELSE 'false' END),
         'data', json(data), 'schemaVersion', schema_version, 'seq', seq
       ) AS j
       FROM records WHERE user_id = ?1 AND seq > ?2 ORDER BY seq LIMIT ?3`,
    )
    .bind(userId, since, limit)
    .all<{ seq: number; j: string }>();
  return results;
}
