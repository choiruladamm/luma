import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/catalog/catalog_query.dart';
import '../../domain/catalog/catalog_row.dart';
import '../database/app_database.dart';

/// Rak bookshelf Gutenberg + jumlah bukunya.
typedef CatalogShelf = ({String name, int count});

/// Keadaan katalog lokal; [count] 0 = belum pernah diunduh.
typedef CatalogStats = ({int count, DateTime? syncedAt, String? lastModified});

/// Katalog lokal Gutenberg di tabel `catalog_books` (docs/discover.md).
/// [search] lewat FTS5 `catalog_fts` (prefix per kata, urut bm25, judul
/// bobot 10× penulis); [byAuthor] / [byBookshelf] cocokin token JSON.
class CatalogRepository {
  CatalogRepository(this._db);

  final AppDatabase _db;
  static const pageSize = 25;

  /// Ganti seluruh isi + index FTS dalam satu transaksi: gagal di tengah =
  /// tabel lama utuh. Meta ([saveMeta]) ditulis service setelah ini sukses.
  Future<void> replaceAll(List<CatalogRow> rows) => _db.transaction(() async {
    await _db.delete(_db.catalogBooks).go();
    // Per 2.000 baris biar satu statement gak nahan 62k variabel di memori.
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

  /// Satu buku by Text#; null kalau gak ada di katalog.
  Future<CatalogRow?> byId(int id) async {
    final row = await (_db.select(
      _db.catalogBooks,
    )..where((b) => b.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toRow(row);
  }

  /// Tiap kata [query] jadi prefix (`jane au` → Jane Austen), semua kata
  /// harus ketemu di judul atau penulis. Urut relevansi bm25 (judul 10×
  /// penulis), seri → judul. Query tanpa kata = kosong: daftar populer bukan
  /// urusan katalog lokal.
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

  /// Total hasil [search], buat "N hasil" dan tahu masih ada halaman.
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

  /// Buku dari [name] persis (nama kayak di `authors`), urut judul.
  Future<List<CatalogRow>> byAuthor(String name, {int page = 1}) =>
      _page(_authorWhere(name), page);

  /// Jumlah buku [name] di katalog, buat "N buku lain".
  Future<int> countByAuthor(String name) => _total(_authorWhere(name));

  Future<List<CatalogRow>> byBookshelf(String name, {int page = 1}) =>
      _page((b) => _has(b.bookshelvesJson, _json(name)), page);

  _Where _authorWhere(String name) =>
      (b) => _has(b.authorsJson, _json({'name': name}));

  /// `"name":"Austen, Jane"` / `"Harvard Classics"`: cocokin token JSON
  /// persis, tanpa kolom pivot.
  static String _json(Object value) {
    final s = jsonEncode(value);
    return value is Map ? s.substring(1, s.length - 1) : s;
  }

  /// `instr(lower(col), lower(q)) > 0`: substring polos buat token JSON,
  /// `%` dan `_` bukan wildcard (LIKE butuh ESCAPE).
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

  /// Semua bookshelf + jumlah buku, terbanyak dulu.
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

  /// [lastModified] = header `Last-Modified` dump, dikirim balik sebagai
  /// `If-Modified-Since`. Null = jangan ubah yang tersimpan.
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

  static CatalogRow _toRow(CatalogBook b) => CatalogRow(
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

/// Jumlah buku + kapan terakhir sync (baris Katalog buku di Pengaturan).
final catalogStatsProvider = StreamProvider<CatalogStats>(
  (ref) => ref.watch(catalogRepositoryProvider).watchStats(),
);
