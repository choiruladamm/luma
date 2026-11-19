import { z } from "zod";

/** `PUT /v1/backups` and an item of the list. */
export const backupInfo = z.strictObject({
  id: z.string(),
  createdAt: z.string(),
  size: z.number(),
  books: z.number(),
  aiResults: z.number(),
  schemaVersion: z.number(),
  appVersion: z.string(),
});
export type BackupInfo = z.infer<typeof backupInfo>;

/** `GET /v1/backups`, newest first. */
export const backupsListResponse = z.strictObject({ backups: z.array(backupInfo) });

/** Backup ids are `yyyyMMddTHHmmssZ`: lexical order = chronological order, so `R2.list` is already chronological. */
export const BACKUP_ID = /^\d{8}T\d{6}Z$/;

/**
 * `PUT /v1/backups` `x-backup-manifest` header: the zip's `manifest.json` as single-line JSON.
 * Loose on purpose: the manifest may carry fields the backend doesn't read.
 */
export const backupManifest = z.object({
  appVersion: z.string().max(40),
  schemaVersion: z.number().int().nonnegative(),
  createdAt: z.string().max(40),
  counts: z.object({
    books: z.number().int().nonnegative(),
    aiResults: z.number().int().nonnegative(),
  }),
});
