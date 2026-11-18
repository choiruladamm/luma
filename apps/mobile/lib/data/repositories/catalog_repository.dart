import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/catalog/catalog_query.dart';
import '../../domain/catalog/catalog_row.dart';
import '../database/app_database.dart';

/// A Gutenberg bookshelf with its book count.
typedef CatalogShelf = ({String name, int count});

/// State of the local catalog; a [count] of 0 means it was never downloaded.
typedef CatalogStats = ({int count, DateTime? syncedAt, String? lastModified});

/// Local Gutenberg catalog in the `catalog_books` table (docs/discover.md).
/// [search] uses FTS5 `catalog_fts` (prefix per word, ordered by bm25, title weighted
/// 10× author); [byAuthor] / [byBookshelf] match JSON tokens.
class CatalogRepository {
  CatalogRepository(this._db);

  final AppDatabase _db;
  static const pageSize = 25;

  /// Replaces all rows and the FTS index in one transaction: a failure midway leaves
  /// the old table intact. The service writes the meta ([saveMeta]) after this succeeds.
  Future<void> replaceAll(List<CatalogRow> rows) => _db.transaction(() async {
    await _db.delete(_db.catalogBooks).go();
    // Insert 2,000 rows at a time so one statement doesn't hold 62k variables in memory.
    for (var i = 0; i < rows.length; i += 2000) {
      final chunk = rows.sublist(i, (i + 2000).clamp(0, rows.length));
      await _db.batch(
        (b) => b.insertAll(_db.catalogBooks, [
          for (final r in chunk)
            CatalogBooksCompanion.insert(
              id: Value(r.id),
              title: r.title,
              authorsText: r.authorsText,
              authorsJson: jsonEncode([for (final a in r.authors) a.toJson()]),
              subjectsJson: jsonEncode(r.subjects),
              bookshelvesJson: jsonEncode(r.bookshelves),
              issued: Value(r.issued),
            ),
        ]),
      );
    }
    await _db.rebuildCatalogFts();
  });

  /// Returns one book by its Gutenberg Text# id, or null if it isn't in the catalog.
  Future<CatalogRow?> byId(int id) async {
    final row = await (_db.select(
      _db.catalogBooks,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toRow(row);
  }

  /// Turns each word of [query] into a prefix (`jane au` → Jane Austen); every word
  /// must match the title or author. Ordered by bm25 relevance (title 10× author),
  /// ties by title. A query without words returns nothing: the popular list is not
  /// the local catalog's job.
  Future<List<CatalogRow>> search(String query, {int page = 1}) async {
    final match = catalogMatchQuery(query);
    if (match == null) return const [];
    final rows = await _db
        .customSelect(
          'SELECT b.* FROM catalog_fts f '
          'JOIN catalog_books b ON b.id = f.rowid '
          'WHERE catalog_fts MATCH ? '
          'ORDER BY bm25(catalog_fts, 10.0, 1.0), b.title LIMIT ? OFFSET ?',
          variables: [
            Variable(match),
            Variable(pageSize),
            Variable((page - 1) * pageSize),
          ],
          readsFrom: {_db.catalogBooks},
        )
        .get();
    return [for (final r in rows) _toRow(_db.catalogBooks.map(r.data))];
  }

  /// Returns the total number of [search] results, for "N hasil" and to know whether more pages exist.
  Future<int> searchCount(String query) async {
    final match = catalogMatchQuery(query);
    if (match == null) return 0;
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM catalog_fts WHERE catalog_fts MATCH ?',
          variables: [Variable(match)],
          readsFrom: {_db.catalogBooks},
        )
        .getSingle();
    return row.read<int>('n');
  }

  /// Returns books by exactly [name] (spelled as in `authors`), ordered by title.
  Future<List<CatalogRow>> byAuthor(String name, {int page = 1}) =>
      _page(_authorWhere(name), page);

  /// Returns the number of books by [name] in the catalog, for "N buku lain".
  Future<int> countByAuthor(String name) => _total(_authorWhere(name));

  Future<List<CatalogRow>> byBookshelf(String name, {int page = 1}) =>
      _page((b) => _has(b.bookshelvesJson, _json(name)), page);

  _Where _authorWhere(String name) =>
      (b) => _has(b.authorsJson, _json({'name': name}));

  /// Matches `"name":"Austen, Jane"` / `"Harvard Classics"` as an exact JSON token,
  /// without a pivot column.
  static String _json(Object value) {
    final s = jsonEncode(value);
    return value is Map ? s.substring(1, s.length - 1) : s;
  }

  /// `instr(lower(col), lower(q)) > 0`: a plain substring match on JSON tokens;
  /// `%` and `_` are not wildcards (LIKE would need ESCAPE).
  static Expression<bool> _has(Expression<String> column, String q) =>
      FunctionCallExpression<int>('instr', [
        column.lower(),
        Constant(q.toLowerCase()),
      ]).isBiggerThanValue(0);

  Future<List<CatalogRow>> _page(_Where where, int page) async {
    final rows =
        await (_db.select(_db.catalogBooks)
              ..where(where)
              ..orderBy([(b) => OrderingTerm.asc(b.title)])
              ..limit(pageSize, offset: (page - 1) * pageSize))
            .get();
    return rows.map(_toRow).toList();
  }

  Future<int> _total(_Where where) async {
    final n = countAll();
    final row =
        await (_db.selectOnly(_db.catalogBooks)
              ..addColumns([n])
              ..where(where(_db.catalogBooks)))
            .getSingle();
    return row.read(n)!;
  }

  /// Returns every bookshelf with its book count, largest first.
  Future<List<CatalogShelf>> bookshelves() async {
    final rows = await _db
        .customSelect(
          'SELECT j.value AS name, COUNT(*) AS n '
          'FROM catalog_books, json_each(catalog_books.bookshelves_json) AS j '
          'GROUP BY j.value ORDER BY n DESC, name',
          readsFrom: {_db.catalogBooks},
        )
        .get();
    return [
      for (final r in rows)
        (name: r.read<String>('name'), count: r.read<int>('n')),
    ];
  }

  Future<CatalogStats> stats() => watchStats().first;

  Stream<CatalogStats> watchStats() =>
      (_db.select(_db.settings)
            ..where((s) => s.key.isIn([_count, _syncedAt, _lastModified])))
          .watch()
          .map((rows) {
            final m = {for (final r in rows) r.key: r.value};
            return (
              count: int.tryParse(m[_count] ?? '') ?? 0,
              syncedAt: DateTime.tryParse(m[_syncedAt] ?? ''),
              lastModified: m[_lastModified],
            );
          })
          .distinct();

  Future<bool> isSynced() async => (await stats()).count > 0;

  /// [lastModified] is the dump's `Last-Modified` header, sent back later as
  /// `If-Modified-Since`. Null leaves the stored value unchanged.
  Future<void> saveMeta({
    required DateTime syncedAt,
    String? lastModified,
    int? count,
  }) => _db.batch(
    (b) => b.insertAllOnConflictUpdate(_db.settings, [
      SettingsCompanion.insert(
        key: _syncedAt,
        value: syncedAt.toIso8601String(),
      ),
      if (lastModified != null)
        SettingsCompanion.insert(key: _lastModified, value: lastModified),
      if (count != null) SettingsCompanion.insert(key: _count, value: '$count'),
    ]),
  );

  static const _count = 'catalog.count';
  static const _syncedAt = 'catalog.syncedAt';
  static const _lastModified = 'catalog.lastModified';

  static CatalogRow _toRow(CatalogBookRow b) => CatalogRow(
    id: b.id,
    title: b.title,
    authors: [
      for (final a in jsonDecode(b.authorsJson) as List)
        CatalogAuthor.fromJson(a as Map<String, Object?>),
    ],
    subjects: (jsonDecode(b.subjectsJson) as List).cast<String>(),
    bookshelves: (jsonDecode(b.bookshelvesJson) as List).cast<String>(),
    issued: b.issued,
  );
}

typedef _Where = Expression<bool> Function($CatalogBooksTable b);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(appDatabaseProvider)),
);

/// Book count and last sync time (the "Katalog buku" row in Pengaturan).
final catalogStatsProvider = StreamProvider<CatalogStats>(
  (ref) => ref.watch(catalogRepositoryProvider).watchStats(),
);
