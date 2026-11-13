import { DAY_MS } from "../../lib/encoding";
import { ApiError } from "../../lib/errors";
import { type Data, type Kind, merge, type SyncRecord } from "./merge";
import { findRecords, pullRows, syncUsage, writeRecords } from "./repo";

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

/** Kuota sync per user dari `vars` (docs/backend.md, Aturan server). */
export type SyncLimits = { storageBytes: number; dailyWrites: number };

export const syncLimits = (env: Env): SyncLimits => ({
  storageBytes: Number(env.SYNC_STORAGE_BYTES),
  dailyWrites: Number(env.SYNC_DAILY_WRITES),
});

/** Ukuran record di D1, rumusnya sama dengan `size` di repo.ts dan backfill migrasi 0005. */
const recordSize = (r: SyncRecord) => r.key.length + (r.data ? JSON.stringify(r.data).length : 0);

/**
 * Tolak batch yang bikin user lewat kuota: baris ditulis per hari UTC (kuota tulis
 * D1 100rb/hari dipakai bareng semua user) → 429 sampai tengah malam UTC; total
 * ukuran record → 413. Batch yang mengecilkan data selalu boleh.
 * ponytail: dicek di luar batch tulis; push paralel bisa lewat maks satu batch
 * (500 baris) per request yang barengan. Cukup selama rate limit per user ada.
 */
function assertQuota(usage: { bytes: number; day: number; rows: number }, limits: SyncLimits, rows: number, bytesDelta: number, now: Date) {
  const day = Math.floor(now.getTime() / DAY_MS);
  const rowsToday = (usage.day === day ? usage.rows : 0) + rows;
  if (rowsToday > limits.dailyWrites) {
    const retryAfter = Math.ceil(((day + 1) * DAY_MS - now.getTime()) / 1000);
    throw new ApiError(429, "QUOTA_EXCEEDED", "Daily sync quota reached", { "Retry-After": String(retryAfter) });
  }
  if (bytesDelta > 0 && usage.bytes + bytesDelta > limits.storageBytes) {
    throw new ApiError(413, "STORAGE_FULL", "Sync storage is full");
  }
  return day;
}

/**
 * Merge batch push ke `records`: 1 SELECT record lama, merge di JS
 * ([merge]), lalu 1 batch atomik yang nulis yang berubah aja (repo.ts).
 * ponytail: merge dibaca di luar transaksi; dua device push key yang sama di
 * milidetik yang sama → yang terakhir nulis menang. Cukup buat satu user.
 */
export async function push(
  d1: D1Database,
  userId: string,
  body: PushBody,
  limits: SyncLimits,
  now = new Date(),
): Promise<PushResult> {
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

  const stored = new Map(existing.map((r) => [id(r), r.size]));
  const current = new Map<string, SyncRecord>(existing.map((r) => [id(r), r]));
  const changed = new Map<string, SyncRecord>();
  for (const r of incoming) {
    const merged = merge(current.get(id(r)), r);
    if (!merged) continue;
    current.set(id(r), merged);
    changed.set(id(r), merged);
  }

  const usage = await syncUsage(d1, userId);
  if (changed.size === 0) return { seq: usage.seq, applied: 0 };
  let bytesDelta = 0;
  for (const [k, r] of changed) bytesDelta += recordSize(r) - (stored.get(k) ?? 0);
  const day = assertQuota(usage, limits, changed.size, bytesDelta, now);
  const seq = await writeRecords(d1, userId, [...changed.values()], { bytesDelta, day });
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
