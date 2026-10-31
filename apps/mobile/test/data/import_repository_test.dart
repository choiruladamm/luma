import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/data/services/chapter_extractor.dart';
import 'package:luma/data/services/epub_parser.dart';
import 'package:luma/data/services/file_storage.dart';

void main() {
  final epub = File('test/fixtures/enchiridion.epub').readAsBytesSync();
  late AppDatabase db;
  late Directory root;
  late FileStorage storage;
  late ImportRepository repo;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    root = await Directory.systemTemp.createTemp('luma_import_');
    storage = FileStorage(root);
    await storage.ensureDirs();
    repo = ImportRepository(db, storage);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<List<String>> storedFiles() async => [
    for (final d in [storage.booksDir, storage.coversDir])
      ...d.listSync().map((f) => f.uri.pathSegments.last),
  ];

  Future<int> count(TableInfo t) async => (await db.select(t).get()).length;

  test('imports book, chapters, paragraphs and files', () async {
    final result = await repo.importEpub(
      epub,
      fileName: 'pg45109-images-3.epub',
    );
    expect(result.duplicate, isFalse);

    final book = await db.select(db.books).getSingle();
    expect(book.id, result.bookId);
    expect(book.title, 'The Enchiridion');
    expect(book.author, 'Epictetus');
    expect(book.hash, hasLength(64));
    expect(book.fileName, '${book.hash}.epub');
    expect(book.coverName, '${book.hash}.jpg');
    expect(book.parserVersion, parserVersion);

    final chapters = await (db.select(
      db.chapters,
    )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();
    expect(chapters, hasLength(59));
    expect(chapters.map((c) => c.sortOrder), List.generate(59, (i) => i));
    final last = chapters.last;
    final lastParas = await (db.select(
      db.paragraphs,
    )..where((p) => p.chapterId.equals(last.id))).get();
    expect(
      book.totalChars,
      last.charOffset + lastParas.fold(0, (n, p) => n + p.content.length),
    );

    final one = chapters.firstWhere((c) => c.title == 'I');
    final first =
        await (db.select(db.paragraphs)
              ..where((p) => p.chapterId.equals(one.id))
              ..orderBy([(p) => OrderingTerm.asc(p.paragraphIndex)]))
            .get();
    expect(first.first.groupIndex, isNull); // heading
    expect(first[1].content, startsWith('There are things which are within'));
    expect(first[1].groupIndex, 0);

    expect(
      await storedFiles(),
      unorderedEquals([book.fileName, book.coverName]),
    );
    expect(await storage.book(book.fileName!).readAsBytes(), epub);
  });

  test('EPUB sections are stored, and backfilled for schema 10 books', () async {
    final discourses = File('test/fixtures/discourses.epub').readAsBytesSync();
    final result = await repo.importEpub(discourses, fileName: 'd.epub');
    Future<List<Chapter>> chapters() =>
        (db.select(db.chapters)
              ..where((c) => c.bookId.equals(result.bookId))
              ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
            .get();
    final fresh = await chapters();
    expect(fresh.first.section, ''); // Imprint, top level
    final third = fresh.where((c) => c.title.startsWith('III:')).toList();
    expect(third.map((c) => c.section), [
      'Discourses › Book I',
      'Discourses › Book II',
      'Discourses › Book III',
      'Discourses › Book IV',
    ]);

    // Simulate a schema 10 import: old short titles, no section.
    await db.customStatement(
      "UPDATE chapters SET section = NULL, title = substr(title, 1, instr(title || ':', ':') - 1) WHERE book_id = ${result.bookId}",
    );
    expect((await chapters()).where((c) => c.title == 'III'), hasLength(4));
    await repo.backfillSections(result.bookId);
    final filled = await chapters();
    expect(filled.map((c) => c.section), fresh.map((c) => c.section));
    expect(filled.map((c) => c.title), fresh.map((c) => c.title));
    expect(filled.map((c) => c.id), fresh.map((c) => c.id));
  });

  test('backfill marks sections empty when the file is gone', () async {
    final result = await repo.importEpub(epub, fileName: 'a.epub');
    await db.customStatement('UPDATE chapters SET section = NULL');
    await storage
        .book((await db.select(db.books).getSingle()).fileName!)
        .delete();
    await repo.backfillSections(result.bookId);
    final rows = await db.select(db.chapters).get();
    expect(rows.every((c) => c.section == ''), isTrue);
  });

  test('the same file twice is a duplicate, nothing new written', () async {
    final first = await repo.importEpub(epub, fileName: 'a.epub');
    final again = await repo.importEpub(epub, fileName: 'renamed.epub');
    expect(again, (bookId: first.bookId, duplicate: true));
    expect(await count(db.books), 1);
    expect(await storedFiles(), hasLength(2));
  });

  test('a file that fails to parse leaves no rows and no files', () async {
    for (final (bytes, name, error) in [
      (Uint8List.fromList([1, 2, 3]), 'junk.epub', EpubError.notEpub),
      (epub, 'book.pdf', EpubError.notEpub),
      (
        Uint8List.sublistView(epub, 0, epub.length ~/ 2),
        'cut.epub',
        EpubError.corrupt,
      ),
    ]) {
      await expectLater(
        repo.importEpub(bytes, fileName: name),
        throwsA(isA<EpubException>().having((e) => e.error, 'error', error)),
        reason: name,
      );
    }
    expect(await count(db.books), 0);
    expect(await storedFiles(), isEmpty);
  });

  test('a database failure rolls back rows and removes copied files', () async {
    await db.customStatement('DROP TABLE paragraphs');
    await expectLater(
      repo.importEpub(epub, fileName: 'a.epub'),
      throwsA(anything),
    );
    expect(await count(db.books), 0);
    expect(await count(db.chapters), 0);
    expect(await storedFiles(), isEmpty);
  });

  test('reports stages in order', () async {
    final stages = <ImportStage>[];
    await repo.importEpub(epub, fileName: 'a.epub', onStage: stages.add);
    expect(stages, ImportStage.values);
  });

  test('progress only goes up, per chapter, and stays under 100%', () async {
    final seen = <double>[];
    await repo.importEpub(epub, fileName: 'a.epub', onProgress: seen.add);
    expect(seen, isNotEmpty);
    expect(seen.reduce((a, b) => a > b ? a : b), lessThan(1));
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
  });

  test('a duplicate stops after reading', () async {
    await repo.importEpub(epub, fileName: 'a.epub');
    final stages = <ImportStage>[];
    await repo.importEpub(epub, fileName: 'a.epub', onStage: stages.add);
    expect(stages, [ImportStage.reading]);
  });

  test('cancelling before saving writes nothing', () async {
    for (final cancelAt in [ImportStage.outline, ImportStage.chapters]) {
      var cancelled = false;
      await expectLater(
        repo.importEpub(
          epub,
          fileName: 'a.epub',
          onStage: (s) => cancelled = cancelled || s == cancelAt,
          isCancelled: () => cancelled,
        ),
        throwsA(isA<ImportCancelled>()),
        reason: '$cancelAt',
      );
    }
    expect(await count(db.books), 0);
    expect(await storedFiles(), isEmpty);
  });
}
