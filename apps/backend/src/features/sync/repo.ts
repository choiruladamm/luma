// Query `records` + `user_storage.seq` (docs/backend.md, Sync antar device).
// SQL mentah, bukan Drizzle, dengan sengaja: batas D1 free (50 query + 100
// parameter per request) bikin batch 500 record harus lewat `json_each` dalam
// satu statement. Tiap fungsi = satu unit anggaran query (lihat komentarnya).
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

/** 1 query: record yang udah ada buat pasangan `(kind, key)` di batch. */
export async function findRecords(d1: D1Database, userId: string, ids: [Kind, string][]) {
  const { results } = await d1
    .prepare(
      `SELECT kind, key, data, updated_at, deleted, schema_version FROM records
       WHERE user_id = ?1 AND (kind, key) IN
         (SELECT json_extract(value, '$[0]'), json_extract(value, '$[1]') FROM json_each(?2))`,
    )
    .bind(userId, JSON.stringify(ids))
    .all<Row>();
  return results.map(fromRow);
}

/** 1 query: `seq` user sekarang (0 kalau belum pernah push). */
export async function currentSeq(d1: D1Database, userId: string) {
  const row = await d1.prepare("SELECT seq FROM user_storage WHERE user_id = ?1").bind(userId).first<{ seq: number }>();
  return row?.seq ?? 0;
}

/**
 * 1 `db.batch()` atomik (2 statement): `seq += n` + satu
 * `INSERT … SELECT FROM json_each` yang ngasih tiap record `seq` baru berurutan.
 * Balikin `seq` terakhir.
 */
export async function writeRecords(d1: D1Database, userId: string, records: SyncRecord[]) {
  const n = records.length;
  const [bump] = await d1.batch<{ seq: number }>([
    d1
      .prepare(
        `INSERT INTO user_storage (user_id, seq) VALUES (?1, ?2)
         ON CONFLICT (user_id) DO UPDATE SET seq = seq + ?2 RETURNING seq`,
      )
      .bind(userId, n),
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
 * 1 query lewat index `records_user_seq`: record dengan `seq` > [since], udah
 * dibentuk jadi JSON di SQL (`data` udah JSON), jadi Worker gak perlu
 * `JSON.parse` 500 record (batas CPU 10ms). Ambil [limit] baris.
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
