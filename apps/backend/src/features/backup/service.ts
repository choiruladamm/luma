import { BACKUP_ID, type BackupInfo, backupManifest } from "@luma/contracts/backend/backups";
import type { Db } from "@luma/core/db/client";
import { addBytes, releaseOnFailure, reserveBytes } from "../../db/user-storage";
import { ApiError } from "../../lib/errors";
import { fixedLength, userPrefix } from "../../lib/storage";

/** Snapshots kept; the rest are deleted in the same `PUT` (docs/backend.md, Files and cloud backups). */
export const BACKUP_RETENTION = 10;

export const backupId = (now: Date) =>
  now
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d+Z$/, "Z");

export const backupsPrefix = (userId: string) => `${userPrefix(userId)}backups/`;

const invalidManifest = () =>
  new ApiError(400, "BAD_REQUEST", "x-backup-manifest must be the backup manifest JSON");

/** The `x-backup-manifest` header = contents of `manifest.json` in the zip (single-line JSON). */
export function parseManifest(header: string | undefined): Record<string, string> {
  let json: unknown;
  try {
    json = JSON.parse(header ?? "");
  } catch {
    throw invalidManifest();
  }
  const result = backupManifest.safeParse(json);
  if (!result.success) throw invalidManifest();
  const parsed = result.data;
  const createdAt = new Date(parsed.createdAt);
  if (Number.isNaN(createdAt.getTime())) throw invalidManifest();
  return {
    appVersion: parsed.appVersion,
    schemaVersion: String(parsed.schemaVersion),
    createdAt: createdAt.toISOString(),
    books: String(parsed.counts.books),
    aiResults: String(parsed.counts.aiResults),
  };
}

const info = (
  prefix: string,
  o: { key: string; size: number; customMetadata?: Record<string, string> },
): BackupInfo => {
  const m = o.customMetadata ?? {};
  return {
    id: o.key.slice(prefix.length).replace(/\.zip$/, ""),
    createdAt: m.createdAt ?? "",
    size: o.size,
    books: Number(m.books ?? 0),
    aiResults: Number(m.aiResults ?? 0),
    schemaVersion: Number(m.schemaVersion ?? 0),
    appVersion: m.appVersion ?? "",
  };
};

/** The oldest objects beyond the newest [keep]. [objects] is ascending (`R2.list` order). */
export const staleBackups = <T>(objects: T[], keep = BACKUP_RETENTION) =>
  objects.slice(0, Math.max(0, objects.length - keep));

/**
 * Stores a DB snapshot + manifest metadata, then removes those past retention.
 * ponytail: two backups in the same second overwrite the same key and `bytes`
 * is counted twice; the trigger is once a day + a manual button, so it's left alone.
 */
export async function putBackup(
  db: Db,
  bucket: R2Bucket,
  quota: number,
  userId: string,
  upload: {
    size: number;
    body: ReadableStream | null;
    metadata: Record<string, string>;
    now?: Date;
  },
): Promise<BackupInfo> {
  await reserveBytes(db, userId, upload.size, quota);
  const prefix = backupsPrefix(userId);
  const key = `${prefix}${backupId(upload.now ?? new Date())}.zip`;
  const stored = await releaseOnFailure(db, userId, upload.size, () =>
    bucket.put(key, fixedLength(upload.body, upload.size), {
      httpMetadata: { contentType: "application/zip" },
      customMetadata: upload.metadata,
    }),
  );
  const listed = await bucket.list({ prefix, limit: 1000 });
  const stale = staleBackups(listed.objects);
  if (stale.length > 0) await bucket.delete(stale.map((o) => o.key));
  const freed = stale.reduce((sum, o) => sum + o.size, 0);
  if (freed > 0) await addBytes(db, userId, -freed);
  return info(prefix, { key, size: stored.size, customMetadata: upload.metadata });
}

/** Newest first, straight from `R2.list` + customMetadata (no D1 table). */
export async function listBackups(bucket: R2Bucket, userId: string): Promise<BackupInfo[]> {
  const prefix = backupsPrefix(userId);
  const listed = await bucket.list({ prefix, limit: 1000, include: ["customMetadata"] });
  return listed.objects.map((o) => info(prefix, o)).toReversed();
}

export async function getBackup(bucket: R2Bucket, userId: string, id: string) {
  const object = BACKUP_ID.test(id) ? await bucket.get(`${backupsPrefix(userId)}${id}.zip`) : null;
  if (!object) throw new ApiError(404, "BACKUP_NOT_FOUND", "Backup not found");
  return object;
}
