import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ai_reply.dart';
import '../../domain/models/book.dart';

part 'app_database.g.dart';

// docs/data-model.md. Path file disimpen sebagai nama file aja; path absolut
// di-resolve saat runtime (container iOS berubah tiap install ulang).

class Books extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceType => textEnum<SourceType>()();

  /// Slug buat nyocokin import Markdown ke buku yang sama. Null buat EPUB.
  TextColumn get bookKey => text().nullable().unique()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get fileName => text().nullable()();

  /// Null = pake cover default.
  TextColumn get coverName => text().nullable()();

  /// Judul/penulis asli EPUB, diisi sekali pas edit pertama. Null =
  /// belum pernah diedit (`originalAuthor` null + `originalTitle` terisi =
  /// aslinya tanpa penulis). Re-import gak boleh nimpa `title`/`author`
  /// kalau `originalTitle` terisi.
  TextColumn get originalTitle => text().nullable()();
  TextColumn get originalAuthor => text().nullable()();

  /// true = cover EPUB disembunyiin; `coverName` tetap utuh di DB + disk.
  BoolColumn get useDefaultCover =>
      boolean().withDefault(const Constant(false))();

  /// SHA-256 isi file EPUB, cegah import dobel.
  TextColumn get hash => text().nullable().unique()();

  /// Naik = re-import + hapus ai_results buku itu.
  IntColumn get parserVersion => integer()();

  /// Snapshot isi/urutan untuk chat; metadata tidak menaikkan revision.
  IntColumn get contentRevision => integer().withDefault(const Constant(1))();
  IntColumn get totalChars => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  DateTimeColumn get firstOpenedAt => dateTime().nullable()();

  /// Total waktu baca aktif (halaman baca kebuka, app di depan, belum idle).
  IntColumn get readingSeconds => integer().withDefault(const Constant(0))();

  /// Pertama kali layar akhir buku kebuka. Diisi sekali, gak ditimpa. Gak
  /// disimpulin dari sesi: lompat ke bab terakhir bisa ngelabuin.
  DateTimeColumn get finishedAt => dateTime().nullable()();
}

/// `id` = kunci stabil yang dirujuk tabel lain; urutan tampil dari
/// [sortOrder], bukan dari id.
@TableIndex(name: 'chapters_book_order', columns: {#bookId, #sortOrder})
class Chapters extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();

  /// Nomor bab asli (Markdown / daftar isi).
  IntColumn get chapterNumber => integer().nullable()();
  TextColumn get title => text()();

  /// Label induk TOC EPUB ("Discourses › Book I"), buat resolusi "bab III"
  /// di Ngobrol. Null = belum diperiksa (buku lama), '' = diperiksa, gak ada.
  TextColumn get section => text().nullable()();

  /// Jumlah karakter sebelum chapter ini, buat persentase baca.
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

  /// Null buat heading & scene break.
  IntColumn get groupIndex => integer().nullable()();
  TextColumn get type => textEnum<ParagraphType>()();

  /// Teks polos yang udah dinormalisasi. (`text` bentrok sama builder Drift.)
  TextColumn get content => text().named('text')();

  @override
  Set<Column> get primaryKey => {chapterId, paragraphIndex};
}

/// Posisi baca terakhir, satu baris per buku.
class ReadingProgress extends Table {
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get chapterId =>
      integer().references(Chapters, #id, onDelete: KeyAction.cascade)();
  IntColumn get paragraphIndex => integer()();

  /// Bagian paragraf yang udah lewat garis atas, 0..1 dari tingginya. Fraksi,
  /// bukan piksel: tinggi paragraf berubah kalau font/ukuran diganti di Aa.
  RealColumn get paragraphOffset => real().withDefault(const Constant(0.0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {bookId};
}

/// Cache hasil LLM per grup. Grup yang udah ada di sini gak manggil LLM lagi.
class AiResults extends Table {
  IntColumn get chapterId =>
      integer().references(Chapters, #id, onDelete: KeyAction.cascade)();
  IntColumn get groupIndex => integer()();

  /// JSON array string, satu item per paragraf di grup (urut).
  TextColumn get translations => text()();

  /// Satu penjelasan buat seluruh grup.
  TextColumn get meaning => text()();
  TextColumn get model => text()();

  /// `aiPromptVersion` waktu dibikin. Lebih lama dari yang sekarang = dianggap
  /// belum ada, diterjemahin ulang pas grupnya dibuka.
  IntColumn get promptVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Berapa kali hasil ini dibuka. Penanda grup yang sering dibaca ulang.
  IntColumn get openCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {chapterId, groupIndex};
}

/// Cache Bedahin per grup (docs/data-model.md). [body] di-parse ulang pas
/// dibaca, jadi `parseBreakdown` tetep satu-satunya sumber kebenaran.
class AiBreakdowns extends Table {
  IntColumn get chapterId =>
      integer().references(Chapters, #id, onDelete: KeyAction.cascade)();
  IntColumn get groupIndex => integer()();

  /// Teks mentah balasan model yang udah lolos `parseBreakdown`.
  TextColumn get body => text()();

  /// `breakdownSourceHash` terjemahan `ai_results` yang dipake. Beda =
  /// terjemahannya udah diganti, rentang kalimat gak berlaku lagi.
  TextColumn get sourceHash => text()();
  TextColumn get model => text()();

  /// `breakdownPromptVersion`. Lebih lama = dianggap belum ada.
  IntColumn get promptVersion => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {chapterId, groupIndex};
}

/// Potongan waktu baca aktif. Log append-only: streak, heatmap, kecepatan
/// baca dihitung lewat query. Satu potongan gak pernah lintas bab (pindah bab
/// selalu nyimpen dulu), jadi lompat lewat daftar isi gak ikut keitung.
@TableIndex(name: 'reading_sessions_book_time', columns: {#bookId, #startedAt})
@TableIndex(name: 'reading_sessions_time', columns: {#startedAt})
class ReadingSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get chapterId =>
      integer().references(Chapters, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startedAt => dateTime()();

  /// Waktu aktif ([ReadingClock] di domain/reading.dart).
  IntColumn get seconds => integer()();

  /// Posisi absolut di buku (karakter) di awal dan akhir potongan. Dua ujung,
  /// bukan satu angka: aturan "berapa yang dianggap beneran dibaca" ada di
  /// query, jadi bisa diganti tanpa ngubah data.
  IntColumn get startChar => integer()();
  IntColumn get endChar => integer()();
}

/// Log request LLM, terpisah dari cache `ai_results` (yang `createdAt`-nya
/// ke-reset tiap retranslate dan barisnya ikut kehapus pas re-import). Dasar
/// statistik biaya dan bantuan AI. FK `setNull`: biaya bulanan gak berubah
/// waktu buku dihapus.
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

  /// Panjang teks target, buat "per 1.000 karakter".
  IntColumn get chars => integer()();

  /// Null = model gak ngirim usage.
  IntColumn get promptTokens => integer().nullable()();
  IntColumn get completionTokens => integer().nullable()();
  RealColumn get costUsd => real().nullable()();
  IntColumn get firstTokenMs => integer().nullable()();
  IntColumn get totalMs => integer().nullable()();

  /// `AiError.name`. Null = sukses.
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Pengaturan yang ikut backup (model ID, preferensi Aa, lastBackupAt).
/// API key gak di sini: di flutter_secure_storage.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Katalog Project Gutenberg dari dump `pg_catalog.csv` (docs/discover.md,
/// Katalog lokal). Bukan data user: diganti utuh tiap sync, gak ikut backup.
/// List disimpen JSON; `authorsText` buat LIKE + tampil.
@TableIndex(name: 'catalog_books_title', columns: {#title})
@TableIndex(name: 'catalog_books_authors', columns: {#authorsText})
class CatalogBooks extends Table {
  /// `Text#` Gutenberg.
  IntColumn get id => integer()();
  TextColumn get title => text()();
  TextColumn get authorsText => text()();

  /// JSON `[{"name":…,"birth":…,"death":…}]` ([CatalogAuthor]).
  TextColumn get authorsJson => text()();
  TextColumn get subjectsJson => text()();
  TextColumn get bookshelvesJson => text()();

  /// `YYYY-MM-DD`, null kalau kosong di dump.
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

  /// JSON ChatScrollAnchor (turnId/blockIndex/alignment), bukan offset pixel.
  TextColumn get scrollAnchor => text().nullable()();
}

@DataClassName('ChatTurnRow')
class ChatTurns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId =>
      integer().references(ChatSessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get sequence => integer()();
  TextColumn get question => text()();

  /// Snapshot JSON tidak menunjuk chapter lewat FK: re-import menjaga arsip.
  TextColumn get quote => text().nullable()();
  TextColumn get answer => text().nullable()();
  TextColumn get sources => text().withDefault(const Constant('[]'))();
  TextColumn get draft => text().withDefault(const Constant(''))();
  TextColumn get exploration => text().nullable()();

  /// Langkah AI (#153), JSON; ditulis sekali di finalize, null pada turn lama.
  TextColumn get steps => text().nullable()();

  /// Teks mentah supaya mapper #116 bisa menangani enum backup yang rusak.
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

/// Catatan generatif per bab untuk pertanyaan seluruh buku (#151): dipakai
/// ulang lintas pertanyaan selama revision + manifest window bab sama. Data
/// turunan: ikut backup, dihapus saat isi berubah atau buku dihapus.
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'luma'));

  /// Call inside the content mutation transaction; EPUB re-import must reuse it.
  /// Snapshots survive paragraph replacement; old attempts become read-only.
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

  // Ubah tabel: naikin versi, tambah langkah di onUpgrade, tambah test di
  // test/data/migration_test.dart. Backup dari versi lama ikut dimigrasi pas
  // di-restore.
  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
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
    },
    // SQLite matiin foreign key secara default; cascade butuh ini.
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  // Test yang lupa override bakal buka DB beneran: koneksinya nahan proses
  // `flutter test` sampe nyangkut. Gagal cepat dengan pesan jelas aja.
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
