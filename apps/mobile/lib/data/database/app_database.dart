import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma/data/repositories/book_search_index.dart'
    show BookSearchIndex;
import 'package:luma/domain/catalog/catalog_row.dart' show CatalogAuthor;
import 'package:luma/domain/reading.dart' show ReadingClock;

import '../../domain/models/ai_reply.dart';
import '../../domain/models/book.dart';
import 'sync_schema.dart';

part 'app_database.g.dart';

// Schema: docs/data-model.md. File paths are stored as file names only;
// absolute paths are resolved at runtime because the iOS container changes on
// every reinstall.

class Books extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceType => textEnum<SourceType>()();

  /// Slug that matches a Markdown import to the same book; null for EPUB.
  TextColumn get bookKey => text().nullable().unique()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get fileName => text().nullable()();

  /// The cover file name; null means the default cover.
  TextColumn get coverName => text().nullable()();

  /// The EPUB's original title and author, filled once on the first edit.
  ///
  /// Null means never edited (`originalAuthor` null with `originalTitle` set
  /// means the original had no author). A re-import must not overwrite
  /// `title` or `author` when `originalTitle` is set.
  TextColumn get originalTitle => text().nullable()();
  TextColumn get originalAuthor => text().nullable()();

  /// Whether the EPUB cover is hidden; `coverName` stays intact in the database and on disk.
  BoolColumn get useDefaultCover =>
      boolean().withDefault(const Constant(false))();

  /// SHA-256 of the EPUB file content, that prevents duplicate imports.
  TextColumn get hash => text().nullable().unique()();

  /// Identity in an external catalog (`BookSource.id` plus the id at that
  /// source), which drives the "already on the shelf" badge.
  ///
  /// Null means a manual import (docs/discover.md).
  TextColumn get sourceId => text().nullable()();
  TextColumn get externalId => text().nullable()();

  /// Raising it triggers a re-import and deletes that book's `ai_results`.
  IntColumn get parserVersion => integer()();

  /// Snapshot of content and order for chat; metadata changes don't raise the revision.
  IntColumn get contentRevision => integer().withDefault(const Constant(1))();
  IntColumn get totalChars => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  DateTimeColumn get firstOpenedAt => dateTime().nullable()();

  /// Total active reading time: reader page open, app in the foreground, not yet idle.
  IntColumn get readingSeconds => integer().withDefault(const Constant(0))();

  /// When the end-of-book screen was first reached; set once and never
  /// overwritten.
  ///
  /// It isn't inferred from sessions because jumping to the last chapter
  /// would fool it.
  DateTimeColumn get finishedAt => dateTime().nullable()();
}

/// The `id` is the stable key other tables reference; the display order comes
/// from [sortOrder], not from the id.
@TableIndex(name: 'chapters_book_order', columns: {#bookId, #sortOrder})
class Chapters extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();

  /// The original chapter number (Markdown or table of contents).
  IntColumn get chapterNumber => integer().nullable()();
  TextColumn get title => text()();

  /// The parent label from the EPUB TOC ("Discourses › Book I"), which lets
  /// Ngobrol resolve "bab III".
  ///
  /// Null means not checked yet (a book imported before this column existed),
  /// and '' means checked with no parent label.
  TextColumn get section => text().nullable()();

  /// The number of characters before this chapter, used for the reading percentage.
  IntColumn get charOffset => integer()();
}

@TableIndex(
  name: 'paragraphs_chapter_group',
  columns: {#chapterId, #groupIndex},
)
class Paragraphs extends Table {
  IntColumn get chapterId =>
      integer().references(Chapters, #id, onDelete: KeyAction.cascade)();
  IntColumn get paragraphIndex => integer()();

  /// Null for headings and scene breaks.
  IntColumn get groupIndex => integer().nullable()();
  TextColumn get type => textEnum<ParagraphType>()();

  /// The normalized plain text. The Dart name is `content` because `text` clashes with the Drift builder.
  TextColumn get content => text().named('text')();

  @override
  Set<Column> get primaryKey => {chapterId, paragraphIndex};
}

/// The last reading position, one row per book.
class ReadingProgress extends Table {
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get chapterId =>
      integer().references(Chapters, #id, onDelete: KeyAction.cascade)();
  IntColumn get paragraphIndex => integer()();

  /// The part of the paragraph already past the top line, as a 0..1 fraction
  /// of its height. It is a fraction, not pixels, because the paragraph height
  /// changes when the font or size is changed in Aa.
  RealColumn get paragraphOffset => real().withDefault(const Constant(0.0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {bookId};
}

/// Cache of LLM results per group; a group that is already here doesn't call the LLM again.
class AiResults extends Table {
  IntColumn get chapterId =>
      integer().references(Chapters, #id, onDelete: KeyAction.cascade)();
  IntColumn get groupIndex => integer()();

  /// A JSON array of strings, one item per paragraph in the group, in order.
  TextColumn get translations => text()();

  /// One explanation for the whole group.
  TextColumn get meaning => text()();
  TextColumn get model => text()();

  /// The `aiPromptVersion` at creation time.
  ///
  /// A result older than the current version counts as missing and is
  /// translated again when its group is opened.
  IntColumn get promptVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// How many times this result was opened; marks groups that are reread often.
  IntColumn get openCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {chapterId, groupIndex};
}

/// Cache of Bedahin results per group (docs/data-model.md).
///
/// [body] is parsed again on every read, so `parseBreakdown` stays the single
/// source of truth.
class AiBreakdowns extends Table {
  IntColumn get chapterId =>
      integer().references(Chapters, #id, onDelete: KeyAction.cascade)();
  IntColumn get groupIndex => integer()();

  /// The raw model reply text that passed `parseBreakdown`.
  TextColumn get body => text()();

  /// The `breakdownSourceHash` of the `ai_results` translation that was used.
  ///
  /// A mismatch means the translation was replaced, so the sentence ranges no
  /// longer apply.
  TextColumn get sourceHash => text()();
  TextColumn get model => text()();

  /// The `breakdownPromptVersion`; an older result counts as missing.
  IntColumn get promptVersion => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {chapterId, groupIndex};
}

/// Slices of active reading time, kept as an append-only log; streaks,
/// heatmaps, and reading speed are computed by queries.
///
/// A slice never spans chapters (changing chapter always saves first), so
/// jumping through the table of contents isn't counted.
@TableIndex(name: 'reading_sessions_book_time', columns: {#bookId, #startedAt})
@TableIndex(name: 'reading_sessions_time', columns: {#startedAt})
class ReadingSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get chapterId =>
      integer().references(Chapters, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startedAt => dateTime()();

  /// Active seconds, as measured by [ReadingClock] in domain/reading.dart.
  IntColumn get seconds => integer()();

  /// Absolute book positions (in characters) at the start and end of the
  /// slice.
  ///
  /// Two endpoints rather than one number: the rule for how much counts as
  /// actually read lives in the queries, so it can change without changing the
  /// data.
  IntColumn get startChar => integer()();
  IntColumn get endChar => integer()();
}

/// Log of LLM requests, separate from the `ai_results` cache (whose
/// `createdAt` resets on every retranslate and whose rows are deleted on
/// re-import).
///
/// It is the basis of the cost and AI-help statistics. The foreign keys use
/// `setNull` so the monthly cost doesn't change when a book is deleted.
class AiCalls extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId => integer().nullable().references(
    Books,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get chapterId => integer().nullable().references(
    Chapters,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get groupIndex => integer().nullable()();
  TextColumn get kind => textEnum<AiCallKind>()();
  TextColumn get model => text()();
  IntColumn get promptVersion => integer()();

  /// Length of the target text, used for "per 1.000 karakter" figures.
  IntColumn get chars => integer()();

  /// Null when the model didn't report usage.
  IntColumn get promptTokens => integer().nullable()();
  IntColumn get completionTokens => integer().nullable()();
  RealColumn get costUsd => real().nullable()();
  IntColumn get firstTokenMs => integer().nullable()();
  IntColumn get totalMs => integer().nullable()();

  /// The `AiError.name`; null means success.
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Null for rows written before the key source was recorded.
  TextColumn get keySource => textEnum<AiKeySource>().nullable()();
}

/// Settings that are included in backups (model ID, Aa preferences,
/// lastBackupAt).
///
/// API keys aren't stored here; they live in flutter_secure_storage.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// The Project Gutenberg catalog from the `pg_catalog.csv` dump (docs/discover.md,
/// Local catalog and search).
///
/// It isn't user data: every sync replaces it entirely and backups skip it.
/// Lists are stored as JSON; `authorsText` is for display and the FTS index.
/// Search goes through the virtual table `catalog_fts`
/// ([AppDatabase.createCatalogFts]), which can't be declared as a Drift
/// table.
@TableIndex(name: 'catalog_books_title', columns: {#title})
@TableIndex(name: 'catalog_books_authors', columns: {#authorsText})
@DataClassName('CatalogBookRow')
class CatalogBooks extends Table {
  /// The Gutenberg `Text#`.
  IntColumn get id => integer()();
  TextColumn get title => text()();
  TextColumn get authorsText => text()();

  /// JSON `[{"name":…,"birth":…,"death":…}]` ([CatalogAuthor]).
  TextColumn get authorsJson => text()();
  TextColumn get subjectsJson => text()();
  TextColumn get bookshelvesJson => text()();

  /// `YYYY-MM-DD`; null when the dump leaves it empty.
  TextColumn get issued => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(
  name: 'chat_sessions_book_opened',
  columns: {#bookId, #lastOpenedAt, #id},
)
@DataClassName('ChatSessionRow')
class ChatSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get contentRevision => integer()();
  TextColumn get title => text()();
  BoolColumn get manualTitle => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();

  /// A JSON ChatScrollAnchor (turnId/blockIndex/alignment), not a pixel offset.
  TextColumn get scrollAnchor => text().nullable()();
}

@DataClassName('ChatTurnRow')
class ChatTurns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId =>
      integer().references(ChatSessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get sequence => integer()();
  TextColumn get question => text()();

  /// Snapshot JSON that doesn't reference chapters through a foreign key, so a re-import keeps the archive.
  TextColumn get quote => text().nullable()();
  TextColumn get answer => text().nullable()();
  TextColumn get sources => text().withDefault(const Constant('[]'))();
  TextColumn get draft => text().withDefault(const Constant(''))();
  TextColumn get exploration => text().nullable()();

  /// The AI steps as JSON, written once at finalize; null on turns created before this column existed.
  TextColumn get steps => text().nullable()();

  /// Stored as raw text so the chat mapper can handle a corrupt enum value from a backup.
  TextColumn get phase => text()();
  IntColumn get attempt => integer().withDefault(const Constant(1))();
  TextColumn get model => text()();
  IntColumn get promptVersion => integer()();
  TextColumn get error => text().nullable()();
  IntColumn get httpStatus => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId, sequence},
  ];
}

@DataClassName('ChatIndexRow')
class ChatIndexes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get identity => text().unique()();
  TextColumn get manifest => text()();
  IntColumn get chunkCount => integer()();
  BoolColumn get ready => boolean().withDefault(const Constant(false))();
}

/// Generated notes per chapter for whole-book questions, reused across
/// questions while the revision and the chapter window manifest stay the same.
///
/// This is derived data: it is included in backups, and deleted when the
/// content changes or the book is deleted.
@DataClassName('ChatChapterNoteRow')
class ChatChapterNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get contentRevision => integer()();
  IntColumn get chapterId =>
      integer().references(Chapters, #id, onDelete: KeyAction.cascade)();
  TextColumn get manifest => text()();
  IntColumn get policy => integer()();
  TextColumn get model => text()();

  /// JSON `[{"text":…,"anchors":[[paragraphIndex,start,end],…]}]`.
  TextColumn get notes => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  List<Set<Column>> get uniqueKeys => [
    {chapterId, policy},
  ];
}

@DataClassName('ChatVectorRow')
class ChatVectors extends Table {
  IntColumn get indexId =>
      integer().references(ChatIndexes, #id, onDelete: KeyAction.cascade)();
  IntColumn get ordinal => integer()();
  BlobColumn get vector => blob()();
  TextColumn get checksum => text()();
  @override
  Set<Column> get primaryKey => {indexId, ordinal};
}

/// Local changes that haven't been pushed yet (docs/sync-protocol.md, Push and pull).
///
/// SQLite triggers generated from [syncKinds] fill it, not the repository.
/// There is one row per `(kind, key)`, so 100 reading-position updates become
/// one record. A row whose source is gone at push time becomes a tombstone
/// (for kinds that have one) or is dropped.
class SyncOutbox extends Table {
  TextColumn get kind => text()();
  TextColumn get key => text()();

  /// Time of the last change in epoch milliseconds, from the device clock.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {kind, key};
}

/// Pulled records that can't be applied yet because the book is missing, the
/// `parserVersion` differs, or the record's schema is newer than the app.
class SyncInbox extends Table {
  TextColumn get kind => text()();
  TextColumn get key => text()();

  /// The record data as JSON; null means a tombstone.
  TextColumn get data => text().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get schemaVersion => integer()();

  @override
  Set<Column> get primaryKey => {kind, key};
}

@DriftDatabase(
  tables: [
    Books,
    Chapters,
    Paragraphs,
    ReadingProgress,
    AiResults,
    AiBreakdowns,
    ReadingSessions,
    AiCalls,
    Settings,
    ChatSessions,
    ChatTurns,
    ChatIndexes,
    ChatVectors,
    ChatChapterNotes,
    CatalogBooks,
    SyncOutbox,
    SyncInbox,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'luma'));

  /// Invalidates chat state derived from a book's content and bumps its
  /// `content_revision`.
  ///
  /// Call it inside the content mutation transaction; an EPUB re-import must
  /// reuse it. Snapshots survive paragraph replacement; old attempts become
  /// read-only.
  Future<void> contentChanged(int bookId) => transaction(() async {
    await (delete(chatIndexes)..where((i) => i.bookId.equals(bookId))).go();
    await (delete(
      chatChapterNotes,
    )..where((n) => n.bookId.equals(bookId))).go();
    await customUpdate(
      'UPDATE chat_turns SET phase = ?, updated_at = ? '
      'WHERE session_id IN (SELECT id FROM chat_sessions WHERE book_id = ?) '
      "AND phase IN ('preparing', 'retrieving', 'waiting', 'writing', 'slow')",
      variables: [
        Variable('interrupted'),
        Variable(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        Variable(bookId),
      ],
      updates: {chatTurns},
    );
    await customUpdate(
      'UPDATE books SET content_revision = content_revision + 1 WHERE id = ?',
      variables: [Variable(bookId)],
      updates: {books},
    );
  });

  // A table change needs a version bump, a new step in onUpgrade, and a test
  // in test/data/migration_test.dart. Backups from older versions are migrated
  // on restore.
  @override
  int get schemaVersion => 19;

  /// Creates the sync outbox triggers on every synced table ([syncKinds]).
  Future<void> createSyncTriggers() async {
    for (final kind in syncKinds) {
      for (final sql in kind.triggers) {
        await customStatement(sql);
      }
    }
  }

  /// Creates the FTS5 external-content table over `catalog_books`, so the text
  /// isn't stored twice.
  ///
  /// Its content doesn't follow automatically: call [rebuildCatalogFts] every
  /// time `catalog_books` is replaced. `remove_diacritics 2` makes "bronte"
  /// match "Brontë".
  Future<void> createCatalogFts() => customStatement(
    'CREATE VIRTUAL TABLE IF NOT EXISTS catalog_fts USING '
    "fts5(title, authors_text, content='catalog_books', content_rowid='id', "
    "tokenize='unicode61 remove_diacritics 2')",
  );

  Future<void> rebuildCatalogFts() =>
      customStatement("INSERT INTO catalog_fts(catalog_fts) VALUES('rebuild')");

  /// Creates the FTS5 external-content table over `paragraphs` for Cari kata
  /// (docs/book-search.md).
  ///
  /// Triggers keep it current, so imports and re-imports are indexed
  /// automatically; `scene_break` rows are excluded. Rows that predate schema
  /// 17 aren't indexed; [BookSearchIndex.ensureIndexed] fills them lazily. The
  /// delete and update triggers send `'delete'` only for rows that really are
  /// in the index (checked via docsize); otherwise the FTS5 index gets
  /// corrupted. The index is tied to the `paragraphs` rowid and `VACUUM INTO`
  /// (backup) can shift rowids, so a restore must call
  /// [rebuildBookSearchIndex].
  Future<void> createBookSearchFts() async {
    await customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS paragraph_fts USING '
      "fts5(text, content='paragraphs', content_rowid='rowid', "
      "tokenize='unicode61 remove_diacritics 2')",
    );
    const drop =
        'INSERT INTO paragraph_fts(paragraph_fts, rowid, text) '
        "SELECT 'delete', old.rowid, old.text WHERE EXISTS "
        '(SELECT 1 FROM paragraph_fts_docsize WHERE id = old.rowid);';
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS paragraph_fts_ai AFTER INSERT ON '
      'paragraphs BEGIN '
      'INSERT INTO paragraph_fts(rowid, text) SELECT new.rowid, new.text '
      "WHERE new.type != 'sceneBreak'; END",
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS paragraph_fts_ad AFTER DELETE ON '
      'paragraphs BEGIN $drop END',
    );
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS paragraph_fts_au AFTER UPDATE OF text, '
      'type ON paragraphs BEGIN $drop '
      'INSERT INTO paragraph_fts(rowid, text) SELECT new.rowid, new.text '
      "WHERE new.type != 'sceneBreak'; END",
    );
  }

  /// Rebuilds the whole index from `paragraphs` in a single statement.
  Future<void> rebuildBookSearchIndex() => customStatement(
    "INSERT INTO paragraph_fts(paragraph_fts) VALUES('rebuild')",
  );

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await createCatalogFts();
      await createBookSearchFts();
      await createSyncTriggers();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(books, books.firstOpenedAt);
        await m.addColumn(books, books.readingSeconds);
      }
      if (from < 3) {
        await m.addColumn(readingProgress, readingProgress.paragraphOffset);
      }
      if (from < 4) {
        await m.addColumn(aiResults, aiResults.promptVersion);
      }
      if (from < 5) {
        await m.addColumn(books, books.finishedAt);
        await m.addColumn(aiResults, aiResults.openCount);
        await m.addColumn(aiResults, aiResults.lastOpenedAt);
        await m.createTable(readingSessions);
        await m.createIndex(readingSessionsBookTime);
        await m.createIndex(readingSessionsTime);
        await m.createTable(aiCalls);
      }
      if (from < 6) {
        await m.createTable(aiBreakdowns);
      }
      if (from < 7) {
        await m.addColumn(books, books.originalTitle);
        await m.addColumn(books, books.originalAuthor);
        await m.addColumn(books, books.useDefaultCover);
      }
      if (from < 8) {
        await m.addColumn(books, books.contentRevision);
        await m.createTable(chatSessions);
        await m.createIndex(chatSessionsBookOpened);
        await m.createTable(chatTurns);
      }
      if (from >= 8 && from < 10) {
        await m.addColumn(chatTurns, chatTurns.exploration);
      }
      if (from < 9) {
        await m.createTable(chatIndexes);
        await m.createTable(chatVectors);
      }
      if (from < 11) {
        await m.addColumn(chapters, chapters.section);
      }
      if (from < 12) {
        await m.createTable(chatChapterNotes);
      }
      if (from >= 8 && from < 13) {
        await m.addColumn(chatTurns, chatTurns.steps);
      }
      if (from < 14) {
        await m.createTable(catalogBooks);
        await m.createIndex(catalogBooksTitle);
        await m.createIndex(catalogBooksAuthors);
      }
      if (from < 15) {
        await createCatalogFts();
        // A v14 database may already hold catalog rows.
        await rebuildCatalogFts();
      }
      if (from < 16) {
        await m.addColumn(books, books.sourceId);
        await m.addColumn(books, books.externalId);
      }
      if (from < 17) {
        await createBookSearchFts(); // Existing books are indexed lazily.
      }
      if (from < 18) {
        await m.createTable(syncOutbox);
        await m.createTable(syncInbox);
        // Existing data joins the first sync queue, which is spread over several triggers.
        for (final kind in syncKinds) {
          await customStatement(kind.backfill);
        }
        await createSyncTriggers();
      }
      // Before v5, `createTable(aiCalls)` above already includes the column.
      if (from >= 5 && from < 19) {
        await m.addColumn(aiCalls, aiCalls.keySource);
      }
    },
    // SQLite disables foreign keys by default, and the cascades need them.
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  // A test that forgets the override would open the real database, and its
  // connection keeps the `flutter test` process from exiting. Fail fast with a
  // clear message instead.
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    throw StateError(
      'Tests must override appDatabaseProvider (in-memory DB) or the '
      'providers that read from it.',
    );
  }
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
