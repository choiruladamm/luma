---
type: reference
purpose: Describe mobile backup archives, export, restore, and compatibility.
sections: [Archive contents and manifest, Export and cloud backup, Inspection and restore, Reminder, Compatibility]
---

# Backup and restore

## Archive contents and manifest

A file export is a `luma-backup-YYYYMMDD-HHmm.zip` containing `manifest.json`, the `luma.sqlite` snapshot, and `books/` and `covers/` files. The database snapshot includes settings, chat history and derived data. Secrets in secure storage are excluded.

`BackupManifest` in `apps/mobile/lib/domain/models/backup.dart` defines the manifest. For illustration only:

```json
{
  "format": "luma-backup",
  "formatVersion": 1,
  "appVersion": "0.3.0",
  "schemaVersion": 19,
  "createdAt": "2026-01-01T12:00:00+07:00",
  "counts": { "books": 2, "aiResults": 10 }
}
```

The writer emits `formatVersion: 1`; the reader does not validate that field. Counts describe books and AI result groups. The reader requires format `luma-backup`, an integer `schemaVersion`, a counts map and a parseable `createdAt`. Missing counts default to zero and missing `appVersion` to `?`.

## Export and cloud backup

`BackupService` creates a consistent SQLite snapshot with `VACUUM INTO`, builds the ZIP in an isolate, and offers file exports through the platform share sheet. The app records a successful share as the last backup; Android's unavailable share result is also treated as success.

`CloudBackupRepository` exports a snapshot-only ZIP, uploads missing book and cover files separately, then uploads the snapshot. Signed-in users can trigger a cloud backup manually; `CloudBackupTrigger` also checks on session availability and resume, subject to its timing and non-empty shelf rules. Cloud restore downloads the snapshot and fills missing files before inspection completes. Worker storage and endpoints are in [backend.md](backend.md).

Concurrent cloud backup requests share one run (`CloudBackupRepository`). The archive is built in a temporary directory and handed to the share sheet, so the user chooses where it lives.

## Inspection and restore

`RestoreService.inspect` extracts recognized paths into a temporary directory, checks the manifest and schema version, opens and migrates the snapshot, and rebuilds paragraph FTS before presenting a preview. `VACUUM INTO` can change paragraph rowids. Cloud restore fills referenced files at this stage; missing remote files can be skipped.

After confirmation, `RestoreService.apply` closes active chat work and the database, moves existing files aside, and installs the snapshot and folders. If a move in the swap fails, it attempts to reverse completed moves in reverse order; rollback itself can fail. Cleanup after a successful swap can also fail. The caller invalidates `appDatabaseProvider` on success or failure to reopen the database and rebuild its dependents.

Extraction accepts only `manifest.json`, `luma.sqlite`, and one level of plain file names under `books/` and `covers/` (`RestoreService._target`); absolute, traversing, and nested entries are skipped. A cloud restore reuses book and cover files that already exist on the device and downloads only the missing ones.

## Reminder

`backupReminderDays` counts calendar days from the last backup, or the first imported book if none exists. The shelf reminder starts after six days; dismissing it hides it for that calendar day. An empty shelf has no reminder.

## Compatibility

Inspection rejects a backup whose manifest schema is newer than the app; older databases are migrated on the temporary copy. A compatible schema alone does not guarantee an older app understands newer content types. File names in the database are resolved against the current device's documents directory. Restore replaces local data rather than merging it.
