import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/book_search.dart';
import '../../domain/models/book_search.dart';
import '../database/app_database.dart';

/// Cari kata di satu buku lewat `paragraph_fts` + riwayat cari
/// (docs/book-search.md). Index-nya diisi [BookSearchIndex].
class BookSearchRepository {
  BookSearchRepository(this._db);

  final AppDatabase _db;

  static const _from =
      'FROM paragraph_fts f '
      'JOIN paragraphs p ON p.rowid = f.rowid '
      'JOIN chapters c ON c.id = p.chapter_id '
      'WHERE paragraph_fts MATCH ? AND c.book_id = ?';

  /// Paragraf yang cocok, urut bab sesuai buku lalu urut paragraf. Query
  /// kurang dari 2 huruf/angka = kosong. Maks [bookSearchMaxHits] paragraf
  /// dikembaliin; [BookSearchResult.total] tetap jumlah sebenarnya.
  Future<BookSearchResult> search(int bookId, String input) async {
    final query = BookSearchQuery.parse(input);
    if (query == null) return BookSearchResult.empty;
    final vars = [Variable(query.match), Variable(bookId)];
    final rows = await _db
        .customSelect(
          'SELECT p.chapter_id, p.paragraph_index, p.group_index, p.text, '
          'c.title, c.sort_order $_from '
          'ORDER BY c.sort_order, p.paragraph_index LIMIT ?',
          variables: [...vars, Variable(bookSearchMaxHits + 1)],
          readsFrom: {_db.paragraphs, _db.chapters},
        )
        .get();
    final truncated = rows.length > bookSearchMaxHits;
    final shownRows = truncated ? rows.take(bookSearchMaxHits) : rows;

    final chapters = <BookSearchChapter>[];
    for (final r in shownRows) {
      final id = r.read<int>('chapter_id');
      final text = r.read<String>('text');
      final ranges = query.ranges(text);
      final snip = bookSearchSnippet(
        text,
        ranges.isEmpty ? null : ranges.first,
      );
      final hit = BookSearchHit(
        chapterId: id,
        paragraphIndex: r.read<int>('paragraph_index'),
        groupIndex: r.read<int?>('group_index'),
        snippet: snip.text,
        matchStart: snip.matchStart,
        matchEnd: snip.matchEnd,
      );
      if (chapters.isNotEmpty && chapters.last.chapterId == id) {
        chapters.last.hits.add(hit);
      } else {
        chapters.add(
          BookSearchChapter(
            chapterId: id,
            title: r.read<String>('title'),
            sortOrder: r.read<int>('sort_order'),
            hits: [hit],
          ),
        );
      }
    }
    if (!truncated) {
      return BookSearchResult(
        chapters: chapters,
        total: rows.length,
        chapterCount: chapters.length,
      );
    }
    final count = await _db
        .customSelect(
          'SELECT COUNT(*) AS n, COUNT(DISTINCT c.id) AS chapters $_from',
          variables: vars,
          readsFrom: {_db.paragraphs, _db.chapters},
        )
        .getSingle();
    return BookSearchResult(
      chapters: chapters,
      total: count.read<int>('n'),
      chapterCount: count.read<int>('chapters'),
    );
  }

  /// Pencarian terakhir buku ini, terbaru dulu (maks 5).
  Future<List<String>> recentSearches(int bookId) async {
    final row =
        await (_db.select(_db.settings)
              ..where((s) => s.key.equals(bookSearchRecentKey(bookId))))
            .getSingleOrNull();
    if (row == null) return const [];
    try {
      return [for (final q in jsonDecode(row.value) as List) q as String];
    } on Object {
      return const []; // rusak = anggap kosong, gak perlu crash
    }
  }

  /// Dipanggil pas user tap hasil (bukan tiap ketikan). Query yang sama
  /// (abaikan besar/kecil) naik ke paling atas.
  Future<void> saveRecent(int bookId, String input) async {
    final q = input.trim();
    if (BookSearchQuery.parse(q) == null) return;
    final list = [
      q,
      for (final r in await recentSearches(bookId))
        if (r.toLowerCase() != q.toLowerCase()) r,
    ].take(bookSearchMaxRecents).toList();
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: bookSearchRecentKey(bookId),
            value: jsonEncode(list),
          ),
        );
  }

  Future<void> clearRecents(int bookId) => (_db.delete(
    _db.settings,
  )..where((s) => s.key.equals(bookSearchRecentKey(bookId)))).go();
}

final bookSearchRepositoryProvider = Provider<BookSearchRepository>(
  (ref) => BookSearchRepository(ref.watch(appDatabaseProvider)),
);
