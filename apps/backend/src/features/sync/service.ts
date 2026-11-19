import { DAY_MS } from "../../lib/encoding";
import { ApiError } from "../../lib/errors";
import { type Data, type Kind, merge, type SyncRecord } from "./merge";
import { findRecords, pullRows, type StoredRecord, syncUsage, writeRecords } from "./repo";

/** Max records per push (docs/sync-protocol.md, Sync quotas and compatibility). */
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

/** Per-user sync quotas from `vars` (docs/sync-protocol.md, Sync quotas and compatibility). */
export type SyncLimits = { storageBytes: number; dailyWrites: number };

export const syncLimits = (env: Env): SyncLimits => ({
  storageBytes: Number(env.SYNC_STORAGE_BYTES),
  dailyWrites: Number(env.SYNC_DAILY_WRITES),
});

/** Record size in D1, the same formula as `size` in repo.ts and the migration 0005 backfill. */
const recordSize = (r: SyncRecord) => r.key.length + (r.data ? JSON.stringify(r.data).length : 0);

/**
 * Rejects a batch that takes the user over quota: rows are written per UTC day (the D1
 * 100k/day write quota is shared by all users) → 429 until midnight UTC; total
 * record size → 413. A batch that shrinks data is always allowed.
 * ponytail: checked outside the write batch; parallel pushes can get at most one extra batch
 * (500 rows) past it per concurrent request. Fine as long as the per-user rate limit exists.
 */
function assertQuota(
  usage: { bytes: number; day: number; rows: number },
  limits: SyncLimits,
  rows: number,
  bytesDelta: number,
  now: Date,
) {
  const day = Math.floor(now.getTime() / DAY_MS);
  const rowsToday = (usage.day === day ? usage.rows : 0) + rows;
  if (rowsToday > limits.dailyWrites) {
    const retryAfter = Math.ceil(((day + 1) * DAY_MS - now.getTime()) / 1000);
    throw new ApiError(429, "QUOTA_EXCEEDED", "Daily sync quota reached", {
      "Retry-After": String(retryAfter),
    });
  }
  if (bytesDelta > 0 && usage.bytes + bytesDelta > limits.storageBytes) {
    throw new ApiError(413, "STORAGE_FULL", "Sync storage is full");
  }
  return day;
}

/**
 * Merges [incoming] in order against [existing], so a later duplicate key sees the
 * earlier one. Returns one row per changed key (in first-change order, holding its final
 * value) and the size change against the rows as they were in D1.
 */
function mergeBatch(existing: StoredRecord[], incoming: SyncRecord[]) {
  const stored = new Map(existing.map((r) => [id(r), r.size]));
  const current = new Map<string, SyncRecord>(existing.map((r) => [id(r), r]));
  const changed = new Map<string, SyncRecord>();
  for (const r of incoming) {
    const merged = merge(current.get(id(r)), r);
    if (!merged) continue;
    current.set(id(r), merged);
    changed.set(id(r), merged);
  }
  let bytesDelta = 0;
  for (const [k, r] of changed) bytesDelta += recordSize(r) - (stored.get(k) ?? 0);
  return { changed: [...changed.values()], bytesDelta };
}

/**
 * Merges a push batch into `records`: 1 SELECT of the old records, merge in JS
 * ([merge]), then 1 atomic batch that writes only what changed (repo.ts).
 * ponytail: the merge is read outside the transaction; two devices pushing the same key in
 * the same millisecond → last write wins. Enough for a single user.
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

  const { changed, bytesDelta } = mergeBatch(existing, incoming);

  const usage = await syncUsage(d1, userId);
  if (changed.length === 0) return { seq: usage.seq, applied: 0 };
  const day = assertQuota(usage, limits, changed.length, bytesDelta, now);
  const seq = await writeRecords(d1, userId, changed, { bytesDelta, day });
  return { seq, applied: changed.length };
}

/** Max records per pull page. */
export const MAX_PULL_RECORDS = 500;

/**
 * Pull page: records with `seq` > [since] are already JSON from SQL, the Worker only
 * concatenates strings. Fetches [limit] + 1 to know whether another page exists.
 */
export async function pull(
  d1: D1Database,
  userId: string,
  since: number,
  limit: number,
): Promise<string> {
  const results = await pullRows(d1, userId, since, limit + 1);
  const page = results.slice(0, limit);
  const nextSeq = page.at(-1)?.seq ?? since;
  return `{"records":[${page.map((r) => r.j).join(",")}],"nextSeq":${nextSeq},"more":${results.length > limit}}`;
}
