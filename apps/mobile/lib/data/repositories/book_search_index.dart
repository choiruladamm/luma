import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';

/// Isi index Cari kata buat buku yang udah ada sebelum schema 17
/// (docs/book-search.md). Buku baru / re-import ke-index otomatis lewat
/// trigger di `paragraphs`; yang di sini cuma backfill lazy.
class BookSearchIndex {
  BookSearchIndex(this._db);

  final AppDatabase _db;

  static const _unindexed =
      "p.type != 'sceneBreak' AND NOT EXISTS "
      '(SELECT 1 FROM paragraph_fts_docsize d WHERE d.id = p.rowid)';

  /// True kalau semua paragraf buku ini yang perlu di-index udah masuk.
  Future<bool> isIndexed(int bookId) async {
    final row = await _db
        .customSelect(
          'SELECT EXISTS (SELECT 1 FROM paragraphs p '
          'JOIN chapters c ON c.id = p.chapter_id '
          'WHERE c.book_id = ? AND $_unindexed) AS missing',
          variables: [Variable(bookId)],
          readsFrom: {_db.paragraphs, _db.chapters},
        )
        .getSingle();
    return row.read<int>('missing') == 0;
  }

  /// Index paragraf yang belum masuk, per bab (aman diulang / dilanjut kalau
  /// kepotong). [onProgress] dapet pecahan 0..1.
  Future<void> ensureIndexed(
    int bookId, {
    void Function(double fraction)? onProgress,
  }) async {
    final ids =
        await (_db.selectOnly(_db.chapters)
              ..addColumns([_db.chapters.id])
              ..where(_db.chapters.bookId.equals(bookId))
              ..orderBy([OrderingTerm.asc(_db.chapters.sortOrder)]))
            .map((r) => r.read(_db.chapters.id)!)
            .get();
    onProgress?.call(0);
    for (final (i, id) in ids.indexed) {
      await _db.customStatement(
        'INSERT INTO paragraph_fts(rowid, text) '
        'SELECT p.rowid, p.text FROM paragraphs p '
        'WHERE p.chapter_id = ? AND $_unindexed',
        [id],
      );
      onProgress?.call((i + 1) / ids.length);
    }
  }
}

final bookSearchIndexProvider = Provider<BookSearchIndex>(
  (ref) => BookSearchIndex(ref.watch(appDatabaseProvider)),
);
