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
| `ai_calls` | AI request and usage log | `AiCallsRepository` |
| `settings` | Backed-up preferences and backup metadata | `SettingsRepository` |
| `catalog_books` | Local Gutenberg catalog | `CatalogRepository` |
| `chat_sessions`, `chat_turns` | Chat history and snapshots | `ChatRepository` |
| `chat_indexes`, `chat_vectors` | Derived retrieval index | `ChatIndexRepository` |
| `chat_chapter_notes` | Derived chapter notes | `ChatNotesRepository` |
| `sync_outbox`, `sync_inbox` | Pending local and remote records | `SyncRepository`, `SyncApplier`; outbox also has database triggers |

`StatsRepository` reads the Statistik baca numbers from `reading_sessions` and `books.finishedAt` on device, so they work offline and include books read with an own AI key. The counting rules live in `domain/reading_stats.dart`, apart from queries and UI: characters read per session are the forward distance capped at `maxCharsPerSecond`, a streak counts local days and isn't broken by a today without reading yet, and weeks start on Monday. `StatsRepository.watchHabits` reads the sessions of the calendar span plus every reading day, so a streak can reach back further than the calendar. `watchBooks` takes a book's position from its latest session's `endChar`; Markdown books, which have no end, get no time-left estimate. `watchComprehension` counts successful `group` calls per week against `charsRead` of that week's sessions, and ranks chapters by translated groups (`ai_results`, with `open_count`) over their distinct `group_index` values. `watchCosts` sums `ai_calls.cost_usd` per local month, kind, and book; a group whose calls reported no cost stays null.

Reading time counts only while the app is in the foreground and stops after `ReadingClock.idle` without interaction; each session span stays within one chapter and is saved in the same transaction as `books.readingSeconds`.

`ai_calls` holds one row per AI call that reached OpenRouter: an Artinya group (`group`), a Bedahin breakdown (`breakdown`), or a Ngobrolin buku send (`chat`). Retries, repairs and the non-streaming fallback within one call share its row, with their reported usage summed; usage a provider doesn't report stays null, not zero. Failures record the `AiError` name, including the stream timeout and stall (`timeout`). Cache hits, cancelled calls, stale chat attempts, and calls without a key write nothing. `key_source` says whether the user's own key or the subsidy key paid. Chat rows cover the send's completion requests, not its embeddings, and have no first-token time. The foreign keys are set to null on delete, so cost history outlives a deleted book. The log itself is not synced; only its daily rollup leaves the device.

`UsageRepository` sends that rollup to `POST /v2/usage` ([backend.md](backend.md#usage-analytics)) for the dashboard: per local day, `ai_calls` grouped by kind, model, book, and key source (calls, failures, summed tokens, cost that stays null when no call reported one), plus `reading_sessions` seconds per book as `reading` rows. The book is its sync wire key (hash, or `md:{bookKey}`) and title; a deleted book's calls go out without one. Sending is automatic for signed-in users, independent of the sync toggle: `DailyTrigger` calls `sendIfDue` on open and resume, which tries at most once per local day (`usage.attemptedOn`) and sends every day after `usage.sentThrough` up to yesterday, so today goes out the next day. Progress is saved per complete day, so a failure or a 429 quota stop resumes on a later day without resending. Both keys are per device settings and are not synced.

## Identity and content changes

A chapter's `id` is a stable reference; `sortOrder` determines display order. `paragraphIndex` identifies a paragraph within its chapter, and `groupIndex` identifies its translation group. These indices depend on parsing and grouping: changing their assignment requires a `parserVersion` change and re-import, invalidating affected AI results. Both `ai_results` and `ai_breakdowns` use `(chapterId, groupIndex)` identity; clear the book’s caches when parsing or grouping shifts those indices.

Database file references are names, not absolute paths; the app resolves them in its current documents directory. Changes to chapter or paragraph identity go through `AppDatabase.contentChanged(bookId)` within the content transaction. It increments `contentRevision`; metadata edits do not. The first metadata edit saves the original title and author; reverting both clears the original fields.

## Schema versions and migrations

The current schema version is 19. `AppDatabase.migration` uses hand-written `onUpgrade` migrations; follow the `drift-migration` skill when changing the schema.

## Chat snapshots and derived data

Sessions capture a book's content revision. Older revisions are archived and read-only; turn quotes and sources are snapshots, so history remains readable after content changes. Answers are read in formats 1 and 2 by `chat_snapshot.dart`; a missing `formatVersion` means version 1. Unknown phases become interrupted, and corrupt turn payloads surface `invalidResponse`. Exploration checkpoints are accepted according to the current policy in `chat_exploration.dart`.

Indexes, vectors, and chapter notes are derived data. Their identities, manifests and policies govern reuse; content changes invalidate derived data. Chat behavior and retrieval are described in [llm.md](llm.md).

## Indexes and sync

Paragraph search uses FTS. Restore rebuilds that index on the snapshot because `VACUUM INTO` can change paragraph rowids. `syncKinds` in `apps/mobile/lib/data/database/sync_schema.dart` is the authoritative specification of synced records; see [sync-protocol.md](sync-protocol.md) for the protocol.

## Settings and secrets

`SettingsRepository` defines settings keys and defaults, including reader preferences, model, shelf and locale. Settings are included in backups. API keys and session tokens live in secure storage, not the database or backup; see [architecture.md](architecture.md).
