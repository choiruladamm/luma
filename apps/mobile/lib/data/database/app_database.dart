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

  /// SHA-256 isi file EPUB, cegah import dobel.
  TextColumn get hash => text().nullable().unique()();

  /// Naik = re-import + hapus ai_results buku itu.
  IntColumn get parserVersion => integer()();
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

@DriftDatabase(
  tables: [
    Books,
    Chapters,
    Paragraphs,
    ReadingProgress,
    AiResults,
    ReadingSessions,
    AiCalls,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'luma'));

  // Ubah tabel: naikin versi, tambah langkah di onUpgrade, tambah test di
  // test/data/migration_test.dart. Backup dari versi lama ikut dimigrasi pas
  // di-restore.
  @override
  int get schemaVersion => 5;

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
