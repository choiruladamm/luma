---
type: reference
purpose: Reference the mobile database, content identity, and persistence boundaries.
sections: [Storage map, Identity and content changes, Schema versions and migrations, Chat snapshots and derived data, Indexes and sync, Settings and secrets]
---

# Data model

## Storage map

`AppDatabase` in `apps/mobile/lib/data/database/app_database.dart` defines the tables and their columns. Repositories are in `apps/mobile/lib/data/repositories/`.

| Table | Purpose | Owner |
|---|---|---|
| `books`, `chapters`, `paragraphs` | Book metadata and parsed content | `ImportRepository`, `BookRepository` |
| `reading_progress`, `reading_sessions` | Position and reading activity | `ReadingProgressRepository` |
| `ai_results`, `ai_breakdowns` | Group translation and breakdown caches | `AiResultsRepository`, `AiBreakdownsRepository` |
| `ai_calls` | AI request and usage log | `AppDatabase` schema; no production repository writer currently |
| `settings` | Backed-up preferences and backup metadata | `SettingsRepository` |
| `catalog_books` | Local Gutenberg catalog | `CatalogRepository` |
| `chat_sessions`, `chat_turns` | Chat history and snapshots | `ChatRepository` |
| `chat_indexes`, `chat_vectors` | Derived retrieval index | `ChatIndexRepository` |
| `chat_chapter_notes` | Derived chapter notes | `ChatNotesRepository` |
| `sync_outbox`, `sync_inbox` | Pending local and remote records | `SyncRepository`, `SyncApplier`; outbox also has database triggers |

Reading time counts only while the app is in the foreground and stops after `ReadingClock.idle` without interaction; each session span stays within one chapter and is saved in the same transaction as `books.readingSeconds`.

## Identity and content changes

A chapter's `id` is a stable reference; `sortOrder` determines display order. `paragraphIndex` identifies a paragraph within its chapter, and `groupIndex` identifies its translation group. These indices depend on parsing and grouping: changing their assignment requires a `parserVersion` change and re-import, invalidating affected AI results. Both `ai_results` and `ai_breakdowns` use `(chapterId, groupIndex)` identity; clear the book’s caches when parsing or grouping shifts those indices.

Database file references are names, not absolute paths; the app resolves them in its current documents directory. Changes to chapter or paragraph identity go through `AppDatabase.contentChanged(bookId)` within the content transaction. It increments `contentRevision`; metadata edits do not. The first metadata edit saves the original title and author; reverting both clears the original fields.

## Schema versions and migrations

The current schema version is 18. `AppDatabase.migration` uses hand-written `onUpgrade` migrations; follow the `drift-migration` skill when changing the schema.

## Chat snapshots and derived data

Sessions capture a book's content revision. Older revisions are archived and read-only; turn quotes and sources are snapshots, so history remains readable after content changes. Answers are read in formats 1 and 2 by `chat_snapshot.dart`; a missing `formatVersion` means version 1. Unknown phases become interrupted, and corrupt turn payloads surface `invalidResponse`. Exploration checkpoints are accepted according to the current policy in `chat_exploration.dart`.

Indexes, vectors, and chapter notes are derived data. Their identities, manifests and policies govern reuse; content changes invalidate derived data. Chat behavior and retrieval are described in [llm.md](llm.md).

## Indexes and sync

Paragraph search uses FTS. Restore rebuilds that index on the snapshot because `VACUUM INTO` can change paragraph rowids. `syncKinds` in `apps/mobile/lib/data/database/sync_schema.dart` is the authoritative specification of synced records; see [sync-protocol.md](sync-protocol.md) for the protocol.

## Settings and secrets

`SettingsRepository` defines settings keys and defaults, including reader preferences, model, shelf and locale. Settings are included in backups. API keys and session tokens live in secure storage, not the database or backup; see [architecture.md](architecture.md).
