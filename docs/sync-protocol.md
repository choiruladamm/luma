---
type: reference
purpose: Look up the record format and cross-device sync behavior for the mobile app and Worker.
sections: [Records and keys, Push and pull, Merge rules, Book files and Markdown dumps, Sync quotas and compatibility]
---

# Sync protocol

## Records and keys

The Worker stores the latest merged record for each `(user_id, kind, key)`. The authenticated user supplies the scope. Records use natural keys so devices with the same book can share data despite having different SQLite IDs.

| Kind | Key |
|---|---|
| `book` | Source hash for EPUB or PDF, or `md:{bookKey}` for Markdown |
| `reading_progress` | `{bookKey}` |
| `reading_session` | `{bookKey}/{startedAt in epoch ms}` |
| `ai_result`, `ai_breakdown` | `{bookKey}/{chapterSortOrder}/{groupIndex}` |
| `setting` | Setting key from `syncedSettings` |
| `chat_session` | `{bookKey}/{createdAt in epoch ms}` |
| `chat_turn` | `{sessionKey}/{sequence}` |

In this table, a child key's `{bookKey}` is the book's wire key, including the `md:` prefix when applicable. `syncKinds` in mobile `sync_schema.dart` defines the keys, payloads, and triggers. The allowlist includes model selection, language, shelf preferences, theme, and reader preferences. Backup and catalog settings stay local. Live chat phases (`preparing`, `retrieving`, `waiting`, `writing`, `slow`) stay local. Terminal turns can sync, including failed or interrupted turns. Chapter and paragraph rows, catalog tables, and derived chat indexes and vectors are outside the record protocol.

Field names are snake_case on `/v2` and camelCase on `/v1` ([Backend API](backend.md#api-versions)), written here as `/v2` spells them. `data` is opaque and keeps Drift's own casing on both. A pushed record carries `kind`, `key`, `updated_at`, `deleted`, and `data`. Live records require a JSON object for `data`. The Worker stores tombstones with null data. The push envelope supplies `schema_version`. Fields inside `data` use Dart names, with chapter references expressed as sort order and parser version. `updated_at` is the device's change time in UTC ISO 8601 on the wire. D1 stores it as epoch milliseconds and stores `data` as nullable JSON text. Pulled records also carry their `schema_version` and per-user `seq`.

## Push and pull

- **Push** uses `POST /v2/sync/push` with `{schema_version, records}` and returns `{seq, applied}`. SQLite triggers upsert one `sync_outbox` entry per `(kind, key)`. `SyncRepository` walks entries present at the start of the run in bounded batches and sends the current payload for each. It clears acknowledged entries only when their queued timestamp still matches. Unsendable oversized entries and missing non-tombstone rows are discarded. See [Client request policy](budgets.md#client-request-policy) for triggers and retries.
- **Worker push** looks up existing keys with `findRecords`, merges and deduplicates them in JavaScript, and reads the current usage and cursor via `syncUsage`. `writeRecords` atomically updates the cursor and quota counters and upserts the changed records in a two-statement D1 batch. Every changed record receives a new sequence number. A no-op returns the current cursor and zero applied records. `json_each` keeps the number of SQL parameters small for a whole batch.
- **Pull** uses `GET /v2/sync/pull?since=<seq>&limit=<limit>` and returns `{records, next_seq, more}`. `pullRows` selects `seq > since` in ascending order using `records_user_seq` and serializes records in SQL, with the key names of the request's version, so the body is never parsed or re-encoded. The Worker fetches one extra row to set `more`. `next_seq` is the last sequence returned, or the input cursor for an empty page.
- **Mobile apply** resolves natural keys back to local IDs and processes settings, books, and chat sessions before dependent rows. `SyncApplier.apply` commits the page and account-scoped `sync.pullSeq` cursor in the same transaction. The push acknowledgement's `seq` has no effect on the pull cursor. SQLite triggers stay active. Apply clears the generated outbox entries except for results that need to sync back. `sync_inbox` holds records awaiting missing dependencies or compatible app or parser versions. The app retries the inbox after pulling and after importing a missing book.

## Merge rules

| Record | Worker merge in `merge.ts` |
|---|---|
| `book` | Newest record supplies metadata, including `lastOpenedAt`. For two live records, keep the earliest non-null `firstOpenedAt` and `finishedAt` and the largest `readingSeconds`. |
| `reading_session` | Append-only. An existing record wins for the same key. |
| `ai_result`, `ai_breakdown` | Higher `promptVersion` wins, then newer `createdAt`. Comparisons involving a tombstone use `updated_at`. |
| Other kinds | Newest `updated_at` wins. |

Worker timestamp ties favor the stored record. The mobile applier preserves newer queued local data where applicable. It also takes the maximum `lastOpenedAt` when merging live book metadata and retains book outbox entries that contribute local values. Cached AI results use the prompt version and creation time comparison. A received turn leaves a locally running turn in place.

The mobile outbox emits tombstones for deleted books and chat sessions. Cascaded child deletes produce no tombstones. Applying a book tombstone deletes the local book and clears its dependent inbox entries. Book and chat-session tombstones are applied before live-record timestamp comparisons on mobile. Worker merge and quota reads precede the atomic write batch, so concurrent pushes can race on merge outcomes and quota checks.

## Book files and Markdown dumps

Sync uses the [shared file API](backend.md#files-and-cloud-backups). After a push containing book records, `SyncRepository` checks for missing source files, covers, and Markdown dumps in chunks. It uploads missing objects and preserves the book's outbox entry when a transfer fails. A repeat push can retry the transfer without rewriting identical records.

A missing book in the inbox is a download candidate. The app downloads and imports EPUB or PDF source files one at a time, then clears the import-generated book entry from the outbox and retries the inbox. Failed imports or downloads can be retried on a later full sync.

Markdown books use `md-{bookKey}-{contentRevision}.json.gz`. The dump has `format: "luma-markdown"`, `formatVersion: 1`, book identity, revision, parser version, and chapters. Paragraphs are tuples of `[paragraphIndex, groupIndex, type, content]`. A missing book imports the revisioned dump and preserves its grouping. For an existing book, pull applies metadata and leaves its chapters in place.

## Sync quotas and compatibility

- `MAX_PUSH_RECORDS` and `MAX_PULL_RECORDS` cap a request or page at 500 records. The Worker uses `JSON_BODY_LIMIT` for push (1 MiB), and mobile targets the smaller `SyncService.maxBytes` estimate. `SyncRepository.maxBatches` caps each phase of a run.
- `SYNC_DAILY_WRITES` counts changed sync records per user per UTC day. Exceeding it returns 429 `QUOTA_EXCEEDED` with `Retry-After` until midnight UTC. Repeated no-op pushes add zero to the counter.
- `SYNC_STORAGE_BYTES` accounts for the length of record keys and serialized JSON data. A batch that grows usage above the cap returns 413 `STORAGE_FULL`. Non-growing batches still have to pass the daily write check. These are app-level counters in `user_storage`. See [Free-tier limits](budgets.md#free-tier-limits) for Cloudflare's account limits.
- The Worker refuses an incoming record with a lower `schema_version` than the stored version. Mobile holds records with a newer schema version in the inbox. Chapter references require a matching `parserVersion`. Changing `syncKinds` requires a schema migration that reinstalls the SQLite triggers.
