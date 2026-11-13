import { z } from "zod";
import type { Db } from "../../db/client";
import { addBytes, storedBytes } from "../../db/user-storage";
import { ApiError } from "../../lib/errors";
import { assertFits, fixedLength, userPrefix } from "../../lib/storage";

/** Snapshot yang disimpan; sisanya dihapus di `PUT` yang sama (docs/backend.md, Backup cloud). */
export const BACKUP_RETENTION = 10;

/** `yyyyMMddTHHmmssZ`: urut leksikal = urut waktu, jadi `R2.list` udah kronologis. */
export const BACKUP_ID = /^\d{8}T\d{6}Z$/;

export const backupId = (now: Date) => now.toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");

export const backupsPrefix = (userId: string) => `${userPrefix(userId)}backups/`;

const manifestSchema = z.object({
  appVersion: z.string().max(40),
  schemaVersion: z.number().int().nonnegative(),
  createdAt: z.string().max(40),
  counts: z.object({ books: z.number().int().nonnegative(), aiResults: z.number().int().nonnegative() }),
});

/** Header `x-backup-manifest` = isi `manifest.json` di zip (JSON satu baris). */
export function parseManifest(header: string | undefined): Record<string, string> {
  let parsed: z.infer<typeof manifestSchema> | undefined;
  try {
    parsed = manifestSchema.parse(JSON.parse(header ?? ""));
  } catch {
    parsed = undefined;
  }
  const createdAt = parsed ? new Date(parsed.createdAt) : undefined;
  if (!parsed || !createdAt || Number.isNaN(createdAt.getTime())) {
    throw new ApiError(400, "BAD_REQUEST", "x-backup-manifest must be the backup manifest JSON");
  }
  return {
    appVersion: parsed.appVersion,
    schemaVersion: String(parsed.schemaVersion),
    createdAt: createdAt.toISOString(),
    books: String(parsed.counts.books),
    aiResults: String(parsed.counts.aiResults),
  };
}

export type BackupInfo = {
  id: string;
  createdAt: string;
  size: number;
  books: number;
  aiResults: number;
  schemaVersion: number;
  appVersion: string;
};

const info = (prefix: string, o: { key: string; size: number; customMetadata?: Record<string, string> }): BackupInfo => {
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

/** Objek terlama di luar [keep] terbaru. [objects] urut naik (urutan `R2.list`). */
export const staleBackups = <T>(objects: T[], keep = BACKUP_RETENTION) =>
  objects.slice(0, Math.max(0, objects.length - keep));

/**
 * Simpan snapshot DB + metadata manifest, lalu buang yang lewat retensi.
 * ponytail: dua backup di detik yang sama menimpa key yang sama dan `bytes`
 * terhitung dobel; pemicu cuma 1×/hari + tombol manual, jadi dibiarkan.
 */
export async function putBackup(
  db: Db,
  bucket: R2Bucket,
  quota: number,
  userId: string,
  upload: { size: number; body: ReadableStream | null; metadata: Record<string, string>; now?: Date },
): Promise<BackupInfo> {
  assertFits(await storedBytes(db, userId), upload.size, quota);
  const prefix = backupsPrefix(userId);
  const key = `${prefix}${backupId(upload.now ?? new Date())}.zip`;
  const stored = await bucket.put(key, fixedLength(upload.body, upload.size), {
    httpMetadata: { contentType: "application/zip" },
    customMetadata: upload.metadata,
  });
  const listed = await bucket.list({ prefix, limit: 1000 });
  const stale = staleBackups(listed.objects);
  if (stale.length > 0) await bucket.delete(stale.map((o) => o.key));
  const freed = stale.reduce((sum, o) => sum + o.size, 0);
  await addBytes(db, userId, upload.size - freed);
  return info(prefix, { key, size: stored!.size, customMetadata: upload.metadata });
}

/** Terbaru dulu, langsung dari `R2.list` + customMetadata (tanpa tabel D1). */
export async function listBackups(bucket: R2Bucket, userId: string): Promise<BackupInfo[]> {
  const prefix = backupsPrefix(userId);
  const listed = await bucket.list({ prefix, limit: 1000, include: ["customMetadata"] });
  return listed.objects.map((o) => info(prefix, o)).reverse();
}

export async function getBackup(bucket: R2Bucket, userId: string, id: string) {
  const object = BACKUP_ID.test(id) ? await bucket.get(`${backupsPrefix(userId)}${id}.zip`) : null;
  if (!object) throw new ApiError(404, "BACKUP_NOT_FOUND", "Backup not found");
  return object;
}
