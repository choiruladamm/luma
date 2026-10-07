import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';

/// Posisi baca: chapter (id stabil) + indeks paragraf di chapter itu.
typedef ReadingPosition = ({int chapterId, int paragraphIndex});

class ReadingProgressRepository {
  ReadingProgressRepository(this._db);

  final AppDatabase _db;

  Future<ReadingPosition?> load(int bookId) async {
    final row = await (_db.select(
      _db.readingProgress,
    )..where((p) => p.bookId.equals(bookId))).getSingleOrNull();
    return row == null
        ? null
        : (chapterId: row.chapterId, paragraphIndex: row.paragraphIndex);
  }

  Future<void> save(int bookId, ReadingPosition position) => _db
      .into(_db.readingProgress)
      .insertOnConflictUpdate(
        ReadingProgressCompanion.insert(
          bookId: Value(bookId),
          chapterId: position.chapterId,
          paragraphIndex: position.paragraphIndex,
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Buku dibuka: naik ke depan rak, stiker "Baru" ilang. Pertama kali
  /// dibuka dicatet sekali.
  Future<void> markOpened(int bookId) {
    final now = Variable(DateTime.now());
    return (_db.update(_db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion.custom(
        lastOpenedAt: now,
        firstOpenedAt: coalesce([_db.books.firstOpenedAt, now]),
      ),
    );
  }

  /// Nambahin waktu baca aktif ke total buku.
  Future<void> addReadingTime(int bookId, int seconds) =>
      (_db.update(_db.books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion.custom(
          readingSeconds: _db.books.readingSeconds + Variable(seconds),
        ),
      );
}

final readingProgressRepositoryProvider = Provider<ReadingProgressRepository>(
  (ref) => ReadingProgressRepository(ref.watch(appDatabaseProvider)),
);
