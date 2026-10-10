import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/data/repositories/reading_progress_repository.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/domain/luma_markdown.dart';
import 'package:luma/domain/models/book.dart';

ParsedMarkdown md(String body, {String? title}) =>
    parseLumaMarkdown('${title == null ? '' : '## $title\n\n'}$body');

void main() {
  late AppDatabase db;
  late Directory root;
  late ImportRepository repo;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    root = await Directory.systemTemp.createTemp('luma_md_');
    final storage = FileStorage(root);
    await storage.ensureDirs();
    repo = ImportRepository(db, storage);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<MarkdownImportResult> add(
    String body, {
    int? chapter,
    String? title,
    bool replace = false,
    int? bookId,
  }) => repo.importMarkdown(
    md(body),
    bookId: bookId,
    bookKey: 'atomic-habits',
    bookTitle: 'Atomic Habits',
    chapter: chapter,
    chapterTitle: title,
    replace: replace,
  );

  Future<List<Chapter>> chapters() => (db.select(
    db.chapters,
  )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();

  test(
    'new book: markdown source, no file, paragraphs + groups saved',
    () async {
      final r = await add('Satu.\n\nDua.', chapter: 3, title: 'Habit Loop');
      expect((r.created, r.replaced, r.chapter), (true, false, 3));

      final book = await db.select(db.books).getSingle();
      expect(book.id, r.bookId);
      expect(book.sourceType.name, 'markdown');
      expect(book.bookKey, 'atomic-habits');
      expect(book.title, 'Atomic Habits');
      expect((book.hash, book.fileName, book.coverName), (null, null, null));
      expect(book.totalChars, 'Satu.'.length + 'Dua.'.length);

      final c = await db.select(db.chapters).getSingle();
      expect(
        (c.chapterNumber, c.title, c.sortOrder, c.charOffset),
        (3, 'Habit Loop', 0, 0),
      );
      final paras = await (db.select(
        db.paragraphs,
      )..orderBy([(p) => OrderingTerm.asc(p.paragraphIndex)])).get();
      expect(paras.map((p) => p.content), ['Satu.', 'Dua.']);
      expect(paras.map((p) => p.groupIndex), [0, 0]);
    },
  );

  test(
    'chapters arriving out of order get sorted, offsets recomputed',
    () async {
      await add('aaaa', chapter: 7);
      final r = await add('bb', chapter: 3);
      expect(r.created, isFalse);
      expect(await db.select(db.books).get(), hasLength(1));

      final cs = await chapters();
      expect(cs.map((c) => c.chapterNumber), [3, 7]);
      expect(cs.map((c) => c.sortOrder), [0, 1]);
      expect(cs.map((c) => c.charOffset), [0, 2]);
      expect((await db.select(db.books).getSingle()).totalChars, 6);
    },
  );

  test('no chapter number: last + 1, title falls back to "Bab N"', () async {
    await add('x', chapter: 4);
    final r = await add('y');
    expect(r.chapter, 5);
    expect((await chapters()).last.title, 'Bab 5');
    expect((await add('z', bookId: r.bookId)).chapter, 6);
  });

  test(
    'duplicate number throws, nothing written; replace overwrites',
    () async {
      final first = await add('lama', chapter: 2, title: 'Lama');
      await add('lain', chapter: 3);
      await expectLater(
        add('baru', chapter: 2),
        throwsA(isA<ChapterExists>().having((e) => e.chapter, 'chapter', 2)),
      );
      expect(await db.select(db.paragraphs).get(), hasLength(2));

      // Hasil AI + posisi baca + sesi baca di bab itu.
      await db
          .into(db.aiResults)
          .insert(
            AiResultsCompanion.insert(
              chapterId: first.chapterId,
              groupIndex: 0,
              translations: '["a"]',
              meaning: 'm',
              model: 'x',
            ),
          );
      await db
          .into(db.readingProgress)
          .insert(
            ReadingProgressCompanion.insert(
              bookId: Value(first.bookId),
              chapterId: first.chapterId,
              paragraphIndex: 5,
            ),
          );

      final r = await add(
        'baru banget',
        chapter: 2,
        title: 'Baru',
        replace: true,
      );
      expect((r.replaced, r.chapterId), (true, first.chapterId));
      expect(await db.select(db.aiResults).get(), isEmpty);
      final progress = await db.select(db.readingProgress).getSingle();
      expect((progress.chapterId, progress.paragraphIndex), (r.chapterId, 0));

      final cs = await chapters();
      expect(cs.map((c) => c.title), ['Baru', 'Bab 3']);
      expect(cs.map((c) => c.charOffset), [0, 'baru banget'.length]);
      final paras = await (db.select(
        db.paragraphs,
      )..where((p) => p.chapterId.equals(first.chapterId))).get();
      expect(paras.map((p) => p.content), ['baru banget']);
    },
  );

  test('markFinished never stamps a markdown book', () async {
    final r = await add('x', chapter: 1);
    await ReadingProgressRepository(db).markFinished(r.bookId);
    expect((await db.select(db.books).getSingle()).finishedAt, isNull);
  });

  test('an EPUB is not a valid target', () async {
    final id = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            sourceType: SourceType.epub,
            title: 'E',
            parserVersion: 1,
            totalChars: 0,
          ),
        );
    await expectLater(add('x', bookId: id), throwsArgumentError);
  });
}
