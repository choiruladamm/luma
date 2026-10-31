import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/domain/catalog/catalog_row.dart';
import 'package:luma/domain/catalog/pg_catalog_parser.dart';

void main() {
  late AppDatabase db;
  late CatalogRepository repo;
  final sample = parsePgCatalog(
    File('test/fixtures/catalog/pg_catalog_sample.csv').readAsBytesSync(),
  );

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = CatalogRepository(db);
  });
  tearDown(() => db.close());

  test('replaceAll stores rows; search finds Pride and Prejudice', () async {
    expect(await repo.isSynced(), isFalse);
    await repo.replaceAll(sample);
    await repo.saveMeta(
      syncedAt: DateTime(2026, 10, 31),
      lastModified: 'Sun, 25 Oct 2026 21:41:56 GMT',
      count: sample.length,
    );
    expect(await repo.isSynced(), isTrue);
    expect(await repo.stats(), (
      count: 22,
      syncedAt: DateTime(2026, 10, 31),
      lastModified: 'Sun, 25 Oct 2026 21:41:56 GMT',
    ));

    final hits = await repo.search('austen');
    expect(hits.map((r) => r.id), contains(1342));
    final pp = hits.singleWhere((r) => r.id == 1342);
    expect(pp.title, 'Pride and Prejudice');
    expect(pp.authors, [
      const CatalogAuthor('Austen, Jane', birth: 1775, death: 1817),
    ]);
    expect(pp.bookshelves, contains('Harvard Classics'));
    expect(pp.issued, '1998-06-01');
    // Judul juga kena, case-insensitive.
    expect((await repo.search('PRIDE')).map((r) => r.id), [1342]);
    expect(await repo.search('   '), isEmpty);
    expect(await repo.search('zzzqqq'), isEmpty);
    expect(await repo.searchCount('austen'), hits.length);
    expect(await repo.searchCount(''), 0);
  });

  test('byId returns the row or null', () async {
    await repo.replaceAll(sample);
    expect((await repo.byId(1342))?.title, 'Pride and Prejudice');
    expect(await repo.byId(999999), isNull);
  });

  test('% and _ in the query are plain characters', () async {
    await repo.replaceAll(const [
      CatalogRow(id: 1, title: '100% Proof', authors: []),
      CatalogRow(id: 2, title: '100 Proofs', authors: []),
      CatalogRow(id: 3, title: 'a_b', authors: []),
      CatalogRow(id: 4, title: 'aXb', authors: []),
    ]);
    expect((await repo.search('100%')).map((r) => r.id), [1]);
    expect((await repo.search('a_b')).map((r) => r.id), [3]);
    expect(await repo.searchCount('proof'), 2);
  });

  test('replaceAll swaps everything; failure keeps the old table', () async {
    await repo.replaceAll(sample);
    await repo.replaceAll([
      const CatalogRow(id: 7, title: 'Only', authors: []),
    ]);
    expect((await repo.search('only')).map((r) => r.id), [7]);
    expect(await repo.search('pride'), isEmpty);

    // Duplicate primary key inside the batch → transaction rolls back.
    await expectLater(
      repo.replaceAll(const [
        CatalogRow(id: 1, title: 'A', authors: []),
        CatalogRow(id: 1, title: 'B', authors: []),
      ]),
      throwsA(anything),
    );
    expect((await repo.search('only')).map((r) => r.id), [7]);
  });

  test('paging: 25 per page, ordered by title', () async {
    await repo.replaceAll([
      for (var i = 0; i < 30; i++)
        CatalogRow(
          id: i,
          title: 'Book ${i.toString().padLeft(2, '0')}',
          authors: const [CatalogAuthor('Same, Author')],
        ),
    ]);
    final p1 = await repo.search('book');
    final p2 = await repo.search('book', page: 2);
    expect(p1.length, 25);
    expect(p1.first.title, 'Book 00');
    expect(p2.map((r) => r.title), [
      'Book 25',
      'Book 26',
      'Book 27',
      'Book 28',
      'Book 29',
    ]);
    expect(await repo.search('book', page: 3), isEmpty);
    expect(await repo.searchCount('book'), 30);
    expect((await repo.byAuthor('Same, Author')).length, 25);
    expect(await repo.countByAuthor('Same, Author'), 30);
    expect(await repo.countByAuthor('Nobody'), 0);
  });

  test('byAuthor is exact, byBookshelf matches the shelf name', () async {
    await repo.replaceAll(sample);
    final austen = await repo.byAuthor('Austen, Jane');
    expect(austen.map((r) => r.id), contains(1342));
    expect(await repo.byAuthor('Austen'), isEmpty);
    // Translator counts as a person too.
    expect((await repo.byAuthor('Ormsby, John')).map((r) => r.id), [996]);

    final harvard = await repo.byBookshelf('Harvard Classics');
    expect(harvard.map((r) => r.id), containsAll([1342, 996]));
    expect(await repo.byBookshelf('Harvard'), isEmpty);
  });

  test('bookshelves lists distinct shelves with counts', () async {
    await repo.replaceAll(const [
      CatalogRow(id: 1, title: 'A', authors: [], bookshelves: ['X', 'Y']),
      CatalogRow(id: 2, title: 'B', authors: [], bookshelves: ['X']),
      CatalogRow(id: 3, title: 'C', authors: []),
    ]);
    expect(await repo.bookshelves(), [
      (name: 'X', count: 2),
      (name: 'Y', count: 1),
    ]);
  });

  test('watchStats emits on meta change', () async {
    final seen = <CatalogStats>[];
    final sub = repo.watchStats().listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await repo.saveMeta(syncedAt: DateTime(2026, 10, 31), count: 5);
    await pumpEventQueue();
    expect(seen.map((s) => s.count), [0, 5]);
    expect(seen.last.lastModified, isNull);
  });
}
