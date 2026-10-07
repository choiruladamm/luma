import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/book.dart';
import '../database/app_database.dart';

class BookRepository {
  BookRepository(this._db);

  final AppDatabase _db;

  /// Rak: terakhir dibuka dulu, yang belum pernah dibuka urut baru ditambah.
  Stream<List<ShelfBook>> watchShelf() {
    final q = _db.select(_db.books)
      ..orderBy([
        (b) => OrderingTerm(
          expression: b.lastOpenedAt,
          mode: OrderingMode.desc,
          nulls: NullsOrder.last,
        ),
        (b) => OrderingTerm.desc(b.createdAt),
        (b) => OrderingTerm.desc(b.id),
      ]);
    return q.watch().map((rows) => rows.map(_shelfBook).toList());
  }

  Future<ShelfBook?> book(int id) async {
    final row = await (_db.select(
      _db.books,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
    return row == null ? null : _shelfBook(row);
  }

  /// Buku + chapter-nya buat halaman baca. Null kalau bukunya udah dihapus.
  Future<ReaderBook?> readerBook(int id) async {
    final book = await (_db.select(
      _db.books,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
    if (book == null) return null;
    final rows =
        await (_db.select(_db.chapters)
              ..where((c) => c.bookId.equals(id))
              ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
            .get();
    return ReaderBook(
      id: book.id,
      title: book.title,
      totalChars: book.totalChars,
      chapters: [
        for (final (i, c) in rows.indexed)
          ChapterInfo(
            id: c.id,
            title: c.title,
            charOffset: c.charOffset,
            chars:
                (i + 1 < rows.length
                    ? rows[i + 1].charOffset
                    : book.totalChars) -
                c.charOffset,
          ),
      ],
    );
  }

  Future<List<ReaderParagraph>> paragraphs(int chapterId) async {
    final rows =
        await (_db.select(_db.paragraphs)
              ..where((p) => p.chapterId.equals(chapterId))
              ..orderBy([(p) => OrderingTerm.asc(p.paragraphIndex)]))
            .get();
    return [
      for (final p in rows)
        ReaderParagraph(
          index: p.paragraphIndex,
          groupIndex: p.groupIndex,
          type: p.type,
          text: p.content,
        ),
    ];
  }

  /// Paragraf di chapter ini yang udah diartiin (grupnya ada di ai_results).
  Future<int> translatedInChapter(int chapterId) =>
      _translated('p.chapter_id = ?', chapterId);

  Future<BookEnd?> bookEnd(int bookId) async {
    final book = await (_db.select(
      _db.books,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();
    if (book == null) return null;
    return BookEnd(
      author: book.author,
      coverName: book.coverName,
      startedAt: book.createdAt,
      translated: await _translated('c.book_id = ?', bookId),
    );
  }

  Future<int> _translated(String where, int id) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM paragraphs p '
          'JOIN ai_results a ON a.chapter_id = p.chapter_id '
          'AND a.group_index = p.group_index '
          'JOIN chapters c ON c.id = p.chapter_id '
          'WHERE $where',
          variables: [Variable.withInt(id)],
          readsFrom: {_db.paragraphs, _db.aiResults, _db.chapters},
        )
        .getSingle();
    return row.read<int>('n');
  }

  static ShelfBook _shelfBook(Book b) => ShelfBook(
    id: b.id,
    title: b.title,
    author: b.author,
    coverName: b.coverName,
    opened: b.lastOpenedAt != null,
    createdAt: b.createdAt,
  );
}

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => BookRepository(ref.watch(appDatabaseProvider)),
);
