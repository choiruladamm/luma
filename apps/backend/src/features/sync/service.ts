import { type Data, type Kind, merge, type SyncRecord } from "./merge";

/** Maks record per push (docs/backend.md, Aturan client). */
export const MAX_PUSH_RECORDS = 500;

export type PushRecord = {
  kind: Kind;
  key: string;
  updatedAt: string;
  deleted: boolean;
  data: Data | null;
};
export type PushBody = { schemaVersion: number; records: PushRecord[] };
export type PushResult = { seq: number; applied: number };

type Row = {
  kind: Kind;
  key: string;
  data: string | null;
  updated_at: number;
  deleted: number;
  schema_version: number;
};

const id = (r: { kind: string; key: string }) => `${r.kind}\u0000${r.key}`;

const fromRow = (r: Row): SyncRecord => ({
  kind: r.kind,
  key: r.key,
  data: r.data == null ? null : (JSON.parse(r.data) as Data),
  updatedAt: r.updated_at,
  deleted: r.deleted === 1,
  schemaVersion: r.schema_version,
});

/**
 * Merge batch push ke `records`. Batas D1 free (50 query per request, 100 param
 * per query) bikin upsert per baris gak mungkin, jadi: 1 SELECT record lama lewat
 * `json_each`, merge di JS, lalu satu `db.batch()` atomik: `seq += n` + satu
 * `INSERT … SELECT FROM json_each` yang ngasih tiap record `seq` baru.
 * ponytail: merge dibaca di luar transaksi; dua device push key yang sama di
 * milidetik yang sama → yang terakhir nulis menang. Cukup buat satu user.
 */
export async function push(d1: D1Database, userId: string, body: PushBody): Promise<PushResult> {
  const incoming: SyncRecord[] = body.records.map((r) => ({
    kind: r.kind,
    key: r.key,
    data: r.deleted ? null : r.data,
    updatedAt: Date.parse(r.updatedAt),
    deleted: r.deleted,
    schemaVersion: body.schemaVersion,
  }));

  const { results } = await d1
    .prepare(
      `SELECT kind, key, data, updated_at, deleted, schema_version FROM records
       WHERE user_id = ?1 AND (kind, key) IN
         (SELECT json_extract(value, '$[0]'), json_extract(value, '$[1]') FROM json_each(?2))`,
    )
    .bind(userId, JSON.stringify(incoming.map((r) => [r.kind, r.key])))
    .all<Row>();

  const current = new Map(results.map((r) => [id(r), fromRow(r)]));
  const changed = new Map<string, SyncRecord>();
  for (const r of incoming) {
    const merged = merge(current.get(id(r)), r);
    if (!merged) continue;
    current.set(id(r), merged);
    changed.set(id(r), merged);
  }

  const n = changed.size;
  if (n === 0) {
    const row = await d1.prepare("SELECT seq FROM user_storage WHERE user_id = ?1").bind(userId).first<{ seq: number }>();
    return { seq: row?.seq ?? 0, applied: 0 };
  }

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
      .bind(userId, n, JSON.stringify([...changed.values()])),
  ]);
  return { seq: bump!.results[0]!.seq, applied: n };
}

/** Maks record per halaman pull. */
export const MAX_PULL_RECORDS = 500;

/**
 * Record dengan `seq` > [since], urut `seq`. Tiap record dibentuk jadi JSON di
 * SQL (`data` udah JSON), jadi Worker cuma nyambung string: tanpa
 * `JSON.parse`/`stringify` 500 record (batas CPU 10ms). Satu query lewat index
 * `records_user_seq`; ambil [limit] + 1 buat tahu masih ada halaman berikut.
 */
export async function pull(d1: D1Database, userId: string, since: number, limit: number): Promise<string> {
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
    .bind(userId, since, limit + 1)
    .all<{ seq: number; j: string }>();
  const page = results.slice(0, limit);
  const nextSeq = page.at(-1)?.seq ?? since;
  return `{"records":[${page.map((r) => r.j).join(",")}],"nextSeq":${nextSeq},"more":${results.length > limit}}`;
}
