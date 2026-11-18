import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/book_search.dart';
import '../../domain/models/book.dart';
import '../../domain/models/markdown_shelf.dart';
import '../database/app_database.dart';
import '../services/file_storage.dart';

/// Markdown books on the shelf plus the chapter numbers already present (in display order).
typedef MarkdownBook = ({ShelfBook book, List<int> chapters});

class BookRepository {
  BookRepository(this._db);

  final AppDatabase _db;

  /// Returns the shelf: most recently opened first, never-opened books by when they were added.
  /// Progress comes from the saved position: characters before the chapter, plus characters
  /// of earlier paragraphs, plus the part of the current paragraph already passed.
  Stream<List<ShelfBook>> watchShelf() => _db
      .customSelect(
        'SELECT b.id, b.title, b.author, b.source_type AS src, '
        'c.chapter_number AS cur_number, '
        '(SELECT COALESCE(SUM(LENGTH(text)), 0) FROM paragraphs '
        'WHERE chapter_id = rp.chapter_id) AS cur_total, '
        '(SELECT GROUP_CONCAT(chapter_number) FROM chapters '
        'WHERE book_id = b.id AND chapter_number IS NOT NULL) AS md_numbers, '
        'CASE WHEN b.use_default_cover THEN NULL ELSE b.cover_name END '
        'AS cover_name, b.last_opened_at, '
        'b.created_at, b.total_chars, rp.paragraph_offset AS off, '
        'c.char_offset AS ch_off, '
        '(SELECT COUNT(*) FROM chapters WHERE book_id = b.id) AS ch_count, '
        '(SELECT COUNT(*) FROM chapters '
        'WHERE book_id = b.id AND sort_order <= c.sort_order) AS ch_n, '
        '(SELECT COALESCE(SUM(LENGTH(text)), 0) FROM paragraphs '
        'WHERE chapter_id = rp.chapter_id '
        'AND paragraph_index < rp.paragraph_index) AS before, '
        'COALESCE((SELECT LENGTH(text) FROM paragraphs '
        'WHERE chapter_id = rp.chapter_id '
        'AND paragraph_index = rp.paragraph_index), 0) AS cur, '
        '(rp.paragraph_offset >= 1 AND NOT EXISTS (SELECT 1 FROM paragraphs '
        'WHERE chapter_id = rp.chapter_id '
        'AND paragraph_index > rp.paragraph_index) AND NOT EXISTS '
        '(SELECT 1 FROM chapters '
        'WHERE book_id = b.id AND sort_order > c.sort_order)) AS done '
        'FROM books b '
        'LEFT JOIN reading_progress rp ON rp.book_id = b.id '
        'LEFT JOIN chapters c ON c.id = rp.chapter_id '
        'ORDER BY b.last_opened_at IS NULL, b.last_opened_at DESC, '
        'b.created_at DESC, b.id DESC',
        readsFrom: {
          _db.books,
          _db.readingProgress,
          _db.chapters,
          _db.paragraphs,
        },
      )
      .watch()
      .map((rows) => rows.map(_shelfBook).toList());

  /// Returns Markdown books with their existing chapter numbers, most recently opened first.
  /// Backs the "which book to add to" choice during import.
  Future<List<MarkdownBook>> markdownBooks() async {
    final rows =
        await (_db.select(_db.books)
              ..where((b) => b.sourceType.equalsValue(SourceType.markdown))
              ..orderBy([
                (b) => OrderingTerm(
                  expression: b.lastOpenedAt,
                  mode: OrderingMode.desc,
                  nulls: NullsOrder.last,
                ),
                (b) => OrderingTerm.desc(b.createdAt),
                (b) => OrderingTerm.desc(b.id),
              ]))
            .get();
    return [
      for (final row in rows)
        (
          book: (await book(row.id))!,
          chapters: [
            for (final c
                in await (_db.select(_db.chapters)
                      ..where((c) => c.bookId.equals(row.id))
                      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
                    .get())
              ?c.chapterNumber,
          ],
        ),
    ];
  }

  Future<ShelfBook?> book(int id) async {
    final row = await (_db.select(
      _db.books,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : ShelfBook(
            id: row.id,
            title: row.title,
            author: row.author,
            coverName: row.useDefaultCover ? null : row.coverName,
            opened: row.lastOpenedAt != null,
            createdAt: row.createdAt,
          );
  }

  /// Returns the shelf id of a book that came from an external catalog (drives the
  /// "already on shelf" badge, docs/discover.md), or null when it isn't on the shelf.
  Future<int?> idFromSource(String sourceId, String externalId) async {
    final row =
        await (_db.selectOnly(_db.books)
              ..addColumns([_db.books.id])
              ..where(
                _db.books.sourceId.equals(sourceId) &
                    _db.books.externalId.equals(externalId),
              ))
            .getSingleOrNull();
    return row?.read(_db.books.id);
  }

  /// Watches every `externalId` from [sourceId] that is already on the shelf, so the
  /// "Udah di rak" badge in search results needs no per-row query.
  Stream<Set<String>> watchExternalIds(String sourceId) =>
      (_db.selectOnly(_db.books)
            ..addColumns([_db.books.externalId])
            ..where(_db.books.sourceId.equals(sourceId)))
          .watch()
          .map((rows) => {for (final r in rows) ?r.read(_db.books.externalId)});

  /// Returns the book and its chapters for the reading page, or null if the book was deleted.
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
      contentRevision: book.contentRevision,
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

  /// Returns paragraphs in this chapter that already have a translation (their group is in ai_results).
  Future<int> translatedInChapter(int chapterId) =>
      _translated('p.chapter_id = ?', chapterId);

  Future<BookEnd?> bookEnd(int bookId) async {
    final book = await (_db.select(
      _db.books,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();
    if (book == null) return null;
    return BookEnd(
      author: book.author,
      coverName: book.useDefaultCover ? null : book.coverName,
      readingSeconds: book.readingSeconds,
      translated: await _translated('c.book_id = ?', bookId),
    );
  }

  /// Returns the data for the book Info sheet, or null if the book was deleted.
  Future<BookInfo?> bookInfo(int id, FileStorage files) async {
    final book = await (_db.select(
      _db.books,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
    if (book == null) return null;
    final name = book.fileName;
    final file = name == null ? null : files.book(name);
    return BookInfo(
      originalTitle: book.originalTitle,
      originalAuthor: book.originalAuthor,
      epubCoverName: book.coverName,
      useDefaultCover: book.useDefaultCover,
      lastOpenedAt: book.lastOpenedAt,
      createdAt: book.createdAt,
      fileName: name,
      fileBytes: file != null && await file.exists()
          ? await file.length()
          : null,
      translated: await _translated('c.book_id = ?', id),
    );
  }

  /// Edits title, author, or cover. The original EPUB values are stored once in
  /// `original*` (on the first edit); an edit equal to the original reverts to "not edited".
  Future<void> updateMetadata(
    int id, {
    required String title,
    String? author,
    required bool useDefaultCover,
  }) async {
    final t = title.trim();
    if (t.isEmpty) throw ArgumentError.value(title, 'title', 'kosong');
    final a = (author?.trim().isEmpty ?? true) ? null : author!.trim();
    await _db.transaction(() async {
      final book = await (_db.select(
        _db.books,
      )..where((b) => b.id.equals(id))).getSingleOrNull();
      if (book == null) return;
      final edited = book.originalTitle != null;
      final origTitle = edited ? book.originalTitle! : book.title;
      final origAuthor = edited ? book.originalAuthor : book.author;
      final same = t == origTitle && a == origAuthor;
      await (_db.update(_db.books)..where((b) => b.id.equals(id))).write(
        BooksCompanion(
          title: Value(t),
          author: Value(a),
          originalTitle: Value(same ? null : origTitle),
          originalAuthor: Value(same ? null : origAuthor),
          useDefaultCover: Value(useDefaultCover),
        ),
      );
    });
  }

  /// Deletes a book: rows first (chapters, paragraphs, reading position, and AI
  /// results go via cascade), then the EPUB and cover files. A failed file delete
  /// leaves an orphan file, never an orphan row.
  Future<void> delete(int id, FileStorage files) async {
    final book = await (_db.select(
      _db.books,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
    if (book == null) return;
    await (_db.delete(_db.books)..where((b) => b.id.equals(id))).go();
    // This book's Cari kata history goes too.
    await (_db.delete(
      _db.settings,
    )..where((s) => s.key.equals(bookSearchRecentKey(id)))).go();
    await files.deleteBookFiles(
      fileName: book.fileName,
      coverName: book.coverName,
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

  static ShelfBook _shelfBook(QueryRow r) {
    final total = r.read<int>('total_chars');
    // No saved position: all rp/c columns are null and progress is 0.
    final spot =
        (r.readNullable<int>('ch_off') ?? 0) +
        r.read<int>('before') +
        (r.readNullable<double>('off') ?? 0) * r.read<int>('cur');
    final done = r.readNullable<int>('done') == 1;
    final markdown = r.read<String>('src') == SourceType.markdown.name
        ? _markdownShelf(r)
        : null;
    return ShelfBook(
      id: r.read<int>('id'),
      title: r.read<String>('title'),
      author: r.readNullable<String>('author'),
      coverName: r.readNullable<String>('cover_name'),
      opened: r.readNullable<DateTime>('last_opened_at') != null,
      createdAt: r.read<DateTime>('created_at'),
      progress: done
          ? 1
          : total <= 0
          ? 0
          : (spot / total).clamp(0, 1).toDouble(),
      // A Markdown book has no end, so the total chapter count is unknown.
      finished: done && markdown == null,
      chapter: math.max(1, r.read<int>('ch_n')),
      chapterCount: math.max(1, r.read<int>('ch_count')),
      markdown: markdown,
    );
  }

  static MarkdownShelf _markdownShelf(QueryRow r) {
    final numbers =
        (r.readNullable<String>('md_numbers') ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .map(int.parse)
            .toList()
          ..sort();
    final chapterTotal = r.read<int>('cur_total');
    final inChapter =
        r.read<int>('before') +
        (r.readNullable<double>('off') ?? 0) * r.read<int>('cur');
    return MarkdownShelf(
      chapters: numbers,
      current: r.readNullable<int>('cur_number'),
      fraction: chapterTotal <= 0
          ? 0
          : (inChapter / chapterTotal).clamp(0, 1).toDouble(),
    );
  }
}

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => BookRepository(ref.watch(appDatabaseProvider)),
);
