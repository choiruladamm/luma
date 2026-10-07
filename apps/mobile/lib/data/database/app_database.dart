import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/book.dart';

part 'app_database.g.dart';

// Docs bagian 6. Path file disimpen sebagai nama file aja; path absolut
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
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {chapterId, groupIndex};
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
  tables: [Books, Chapters, Paragraphs, ReadingProgress, AiResults, Settings],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'luma'));

  // Ubah tabel: naikin versi, tambah langkah di onUpgrade, tambah test di
  // test/data/migration_test.dart. Backup dari versi lama ikut dimigrasi pas
  // di-restore.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(books, books.firstOpenedAt);
        await m.addColumn(books, books.readingSeconds);
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
