import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';

/// Fills the Cari kata index for books that existed before schema 17
/// (docs/book-search.md). New and re-imported books are indexed automatically by
/// triggers on `paragraphs`; this class only does a lazy backfill.
class BookSearchIndex {
  BookSearchIndex(this._db);

  final AppDatabase _db;

  static const _unindexed =
      "p.type != 'sceneBreak' AND NOT EXISTS "
      '(SELECT 1 FROM paragraph_fts_docsize d WHERE d.id = p.rowid)';

  /// Returns true when every paragraph of this book that needs indexing is indexed.
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

  /// Indexes the paragraphs still missing, chapter by chapter (safe to repeat or
  /// resume after an interruption). [onProgress] receives (chapters done, chapter count).
  Future<void> ensureIndexed(
    int bookId, {
    void Function(int done, int total)? onProgress,
  }) async {
    final ids =
        await (_db.selectOnly(_db.chapters)
              ..addColumns([_db.chapters.id])
              ..where(_db.chapters.bookId.equals(bookId))
              ..orderBy([OrderingTerm.asc(_db.chapters.sortOrder)]))
            .map((r) => r.read(_db.chapters.id)!)
            .get();
    onProgress?.call(0, ids.length);
    for (final (i, id) in ids.indexed) {
      await _db.customStatement(
        'INSERT INTO paragraph_fts(rowid, text) '
        'SELECT p.rowid, p.text FROM paragraphs p '
        'WHERE p.chapter_id = ? AND $_unindexed',
        [id],
      );
      onProgress?.call(i + 1, ids.length);
    }
  }
}

final bookSearchIndexProvider = Provider<BookSearchIndex>(
  (ref) => BookSearchIndex(ref.watch(appDatabaseProvider)),
);
