import { type Data, type Kind, merge, type SyncRecord } from "./merge";
import { currentSeq, findRecords, pullRows, writeRecords } from "./repo";

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

const id = (r: { kind: string; key: string }) => `${r.kind}\u0000${r.key}`;

/**
 * Merge batch push ke `records`: 1 SELECT record lama, merge di JS
 * ([merge]), lalu 1 batch atomik yang nulis yang berubah aja (repo.ts).
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

  const existing = await findRecords(
    d1,
    userId,
    incoming.map((r) => [r.kind, r.key]),
  );

  const current = new Map(existing.map((r) => [id(r), r]));
  const changed = new Map<string, SyncRecord>();
  for (const r of incoming) {
    const merged = merge(current.get(id(r)), r);
    if (!merged) continue;
    current.set(id(r), merged);
    changed.set(id(r), merged);
  }

  if (changed.size === 0) return { seq: await currentSeq(d1, userId), applied: 0 };
  const seq = await writeRecords(d1, userId, [...changed.values()]);
  return { seq, applied: changed.size };
}

/** Maks record per halaman pull. */
export const MAX_PULL_RECORDS = 500;

/**
 * Halaman pull: record dengan `seq` > [since] udah berupa JSON dari SQL, Worker
 * cuma nyambung string. Ambil [limit] + 1 buat tahu masih ada halaman berikut.
 */
export async function pull(d1: D1Database, userId: string, since: number, limit: number): Promise<string> {
  const results = await pullRows(d1, userId, since, limit + 1);
  const page = results.slice(0, limit);
  const nextSeq = page.at(-1)?.seq ?? since;
  return `{"records":[${page.map((r) => r.j).join(",")}],"nextSeq":${nextSeq},"more":${results.length > limit}}`;
}
