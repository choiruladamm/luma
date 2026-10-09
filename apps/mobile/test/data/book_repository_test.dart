import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/book_repository.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/domain/models/book.dart';

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });
  tearDown(() => db.close());

  Future<int> add(String title, {DateTime? opened, DateTime? created}) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          sourceType: SourceType.epub,
          title: title,
          hash: Value(title),
          parserVersion: 1,
          totalChars: 1,
          lastOpenedAt: Value(opened),
          createdAt: created == null ? const Value.absent() : Value(created),
        ),
      );

  test('shelf: last opened first, then never-opened newest first', () async {
    await add('Old unopened', created: DateTime(2026, 1, 1));
    await add('New unopened', created: DateTime(2026, 2, 1));
    await add('Opened long ago', opened: DateTime(2026, 3, 1));
    await add('Opened today', opened: DateTime(2026, 10, 7));

    final shelf = await BookRepository(db).watchShelf().first;
    expect(shelf.map((b) => (b.title, b.opened)), [
      ('Opened today', true),
      ('Opened long ago', true),
      ('New unopened', false),
      ('Old unopened', false),
    ]);
  });

  test('shelf stream re-emits when a book is imported or deleted', () async {
    final emissions = BookRepository(db)
        .watchShelf()
        .map((s) => s.map((b) => b.title).toList());
    final expectation = expectLater(
      emissions,
      emitsInOrder([
        <String>[],
        ['Meditations'],
        <String>[],
      ]),
    );
    await pumpEventQueue();
    final id = await add('Meditations');
    await pumpEventQueue();
    await (db.delete(db.books)..where((b) => b.id.equals(id))).go();
    await expectation;
  });

  test('readerBook: chapters in order with their lengths', () async {
    final id = await add('Meditations');
    // Inserted out of order on purpose.
    for (final (order, offset) in [(1, 40), (0, 0), (2, 100)]) {
      await db
          .into(db.chapters)
          .insert(
            ChaptersCompanion.insert(
              bookId: id,
              sortOrder: order,
              title: 'Book $order',
              charOffset: offset,
            ),
          );
    }
    await (db.update(db.books)..where((b) => b.id.equals(id))).write(
      const BooksCompanion(totalChars: Value(160)),
    );

    final book = (await BookRepository(db).readerBook(id))!;
    expect(book.title, 'Meditations');
    expect(book.chapters.map((c) => (c.title, c.charOffset, c.chars)), [
      ('Book 0', 0, 40),
      ('Book 1', 40, 60),
      ('Book 2', 100, 60),
    ]);
    expect(await BookRepository(db).readerBook(999), isNull);
  });

  test('paragraphs come back in reading order', () async {
    final id = await add('Meditations');
    final chapterId = await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            bookId: id,
            sortOrder: 0,
            title: 'I',
            charOffset: 0,
          ),
        );
    for (final i in [2, 0, 1]) {
      await db
          .into(db.paragraphs)
          .insert(
            ParagraphsCompanion.insert(
              chapterId: chapterId,
              paragraphIndex: i,
              groupIndex: Value(i == 0 ? null : 0),
              type: i == 0 ? ParagraphType.heading : ParagraphType.paragraph,
              content: 'p$i',
            ),
          );
    }
    final paras = await BookRepository(db).paragraphs(chapterId);
    expect(paras.map((p) => (p.index, p.text, p.groupIndex)), [
      (0, 'p0', null),
      (1, 'p1', 0),
      (2, 'p2', 0),
    ]);
  });

  test('translated paragraphs: per chapter and for the whole book', () async {
    final id = await add('Meditations');
    final other = await add('Enchiridion');
    Future<int> chapter(int bookId, int order) => db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            bookId: bookId,
            sortOrder: order,
            title: 'C$order',
            charOffset: 0,
          ),
        );
    final one = await chapter(id, 0);
    final two = await chapter(id, 1);
    final elsewhere = await chapter(other, 0);
    // Group 0 = paragraphs 0, 1; group 1 = paragraph 3; 2 is a heading.
    for (final ch in [one, two, elsewhere]) {
      for (final (i, g) in [(0, 0), (1, 0), (2, null), (3, 1)]) {
        await db
            .into(db.paragraphs)
            .insert(
              ParagraphsCompanion.insert(
                chapterId: ch,
                paragraphIndex: i,
                groupIndex: Value(g),
                type: g == null
                    ? ParagraphType.heading
                    : ParagraphType.paragraph,
                content: 'p$i',
              ),
            );
      }
    }
    Future<void> translate(int ch, int group) => db
        .into(db.aiResults)
        .insert(
          AiResultsCompanion.insert(
            chapterId: ch,
            groupIndex: group,
            translations: '[]',
            meaning: '',
            model: 'm',
          ),
        );
    await translate(one, 0); // 2 paragraphs
    await translate(two, 1); // 1 paragraph
    await translate(elsewhere, 0); // another book

    final repo = BookRepository(db);
    expect(await repo.translatedInChapter(one), 2);
    expect(await repo.translatedInChapter(two), 1);
    final end = (await repo.bookEnd(id))!;
    expect(end.translated, 3);
    expect(await repo.bookEnd(999), isNull);
  });

  group('shelf progress', () {
    // Two chapters: 20 chars (10 + 10) then 80 chars (30 + 50), 100 total.
    late int bookId, first, second;
    setUp(() async {
      bookId = await add('Walden');
      await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
        const BooksCompanion(totalChars: Value(100)),
      );
      Future<int> chapter(int order, int offset, List<int> lengths) async {
        final id = await db
            .into(db.chapters)
            .insert(
              ChaptersCompanion.insert(
                bookId: bookId,
                sortOrder: order,
                title: 'C$order',
                charOffset: offset,
              ),
            );
        for (final (i, n) in lengths.indexed) {
          await db
              .into(db.paragraphs)
              .insert(
                ParagraphsCompanion.insert(
                  chapterId: id,
                  paragraphIndex: i,
                  groupIndex: Value(i),
                  type: ParagraphType.paragraph,
                  content: 'x' * n,
                ),
              );
        }
        return id;
      }

      first = await chapter(0, 0, [10, 10]);
      second = await chapter(1, 20, [30, 50]);
    });

    Future<ShelfBook> shelfBook() async =>
        (await BookRepository(db).watchShelf().first).single;

    Future<void> readAt(int chapterId, int index, double offset) => db
        .into(db.readingProgress)
        .insertOnConflictUpdate(
          ReadingProgressCompanion.insert(
            bookId: Value(bookId),
            chapterId: chapterId,
            paragraphIndex: index,
            paragraphOffset: Value(offset),
          ),
        );

    test('no saved position: 0%, chapter 1', () async {
      final b = await shelfBook();
      expect(
        (b.progress, b.finished, b.chapter, b.chapterCount),
        (0, false, 1, 2),
      );
    });

    test(
      'chars before the chapter + before the paragraph + the part read',
      () async {
        await readAt(second, 1, 0.5); // 20 + 30 + 25
        final b = await shelfBook();
        expect(b.progress, 0.75);
        expect((b.finished, b.chapter, b.chapterCount), (false, 2, 2));

        await readAt(first, 1, 0); // 10 of 100
        final c = await shelfBook();
        expect(c.progress, 0.1);
        expect(c.chapter, 1);
      },
    );

    test(
      'the end of the last paragraph of the last chapter is finished',
      () async {
        await readAt(second, 1, 1);
        final b = await shelfBook();
        expect((b.progress, b.finished), (1, true));

        // End of an earlier chapter, or a paragraph that is not the last: no.
        await readAt(first, 1, 1);
        expect((await shelfBook()).finished, isFalse);
        await readAt(second, 0, 1);
        expect((await shelfBook()).finished, isFalse);
      },
    );

    test('saving a position re-emits the shelf', () async {
      final emissions = BookRepository(db)
          .watchShelf()
          .map((s) => s.single.progress);
      final expectation = expectLater(emissions, emitsInOrder([0, 0.75]));
      await pumpEventQueue();
      await readAt(second, 1, 0.5);
      await expectation;
    });
  });

  group('info and delete', () {
    late Directory root;
    late FileStorage files;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('luma_books_');
      files = FileStorage(root);
      await files.ensureDirs();
    });
    tearDown(() => root.delete(recursive: true));

    /// A book with a file, a cover and one of everything that points at it.
    Future<int> full(String name) async {
      final id = await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              sourceType: SourceType.epub,
              title: name,
              hash: Value(name),
              fileName: Value('$name.epub'),
              coverName: Value('$name.png'),
              parserVersion: 1,
              totalChars: 10,
              lastOpenedAt: Value(DateTime(2026, 10, 6, 22, 14)),
            ),
          );
      final chapter = await db
          .into(db.chapters)
          .insert(
            ChaptersCompanion.insert(
              bookId: id,
              sortOrder: 0,
              title: 'I',
              charOffset: 0,
            ),
          );
      await db
          .into(db.paragraphs)
          .insert(
            ParagraphsCompanion.insert(
              chapterId: chapter,
              paragraphIndex: 0,
              groupIndex: const Value(0),
              type: ParagraphType.paragraph,
              content: 'hello',
            ),
          );
      await db
          .into(db.readingProgress)
          .insert(
            ReadingProgressCompanion.insert(
              bookId: Value(id),
              chapterId: chapter,
              paragraphIndex: 0,
            ),
          );
      await db
          .into(db.aiResults)
          .insert(
            AiResultsCompanion.insert(
              chapterId: chapter,
              groupIndex: 0,
              translations: '[]',
              meaning: '',
              model: 'm',
            ),
          );
      await files.writeBook('$name.epub', List.filled(2048, 1));
      await files.writeCover('$name.png', [1]);
      return id;
    }

    test('bookInfo: dates, file size, translated paragraphs', () async {
      final id = await full('Walden');
      final info = (await BookRepository(db).bookInfo(id, files))!;
      expect(info.lastOpenedAt, DateTime(2026, 10, 6, 22, 14));
      expect(
        (info.fileName, info.fileBytes, info.translated),
        ('Walden.epub', 2048, 1),
      );
      expect(await BookRepository(db).bookInfo(999, files), isNull);

      await files.deleteBookFiles(fileName: 'Walden.epub');
      expect((await BookRepository(db).bookInfo(id, files))!.fileBytes, isNull);
    });

    test('delete leaves no row and no file behind', () async {
      final gone = await full('Walden');
      final kept = await full('Emma');
      await BookRepository(db).delete(gone, files);

      expect((await db.select(db.books).get()).map((b) => b.id), [kept]);
      for (final left in [
        (await db.select(db.chapters).get()).length,
        (await db.select(db.paragraphs).get()).length,
        (await db.select(db.readingProgress).get()).length,
        (await db.select(db.aiResults).get()).length,
      ]) {
        expect(left, 1); // only Emma's
      }
      expect(await files.book('Walden.epub').exists(), isFalse);
      expect(await files.cover('Walden.png').exists(), isFalse);
      expect(await files.book('Emma.epub').exists(), isTrue);
      expect(await files.cover('Emma.png').exists(), isTrue);

      // A second delete (or a stale id) is a no-op.
      await BookRepository(db).delete(gone, files);
    });

    test('deleting frees the file hash for a re-import', () async {
      final id = await full('Walden');
      await BookRepository(db).delete(id, files);
      expect(await full('Walden'), isNot(id));
    });
  });

  group('updateMetadata', () {
    Future<Book> row(int id) =>
        (db.select(db.books)..where((b) => b.id.equals(id))).getSingle();

    Future<int> addWithAuthor() async {
      final id = await add('pride_FINAL(2)');
      await (db.update(db.books)..where((b) => b.id.equals(id))).write(
        const BooksCompanion(coverName: Value('c.jpg')),
      );
      return id;
    }

    test(
      'first edit keeps the EPUB values; second does not overwrite',
      () async {
        final repo = BookRepository(db);
        final id = await addWithAuthor();
        await repo.updateMetadata(
          id,
          title: '  Pride  ',
          author: ' Jane ',
          useDefaultCover: false,
        );
        var b = await row(id);
        expect((b.title, b.author), ('Pride', 'Jane'));
        expect((b.originalTitle, b.originalAuthor), ('pride_FINAL(2)', null));

        await repo.updateMetadata(
          id,
          title: 'Pride & Prejudice',
          author: 'Jane Austen',
          useDefaultCover: false,
        );
        b = await row(id);
        expect(b.title, 'Pride & Prejudice');
        expect(b.originalTitle, 'pride_FINAL(2)');
      },
    );

    test('editing back to the original resets to "never edited"', () async {
      final repo = BookRepository(db);
      final id = await addWithAuthor();
      await repo.updateMetadata(
        id,
        title: 'X',
        author: 'Y',
        useDefaultCover: false,
      );
      await repo.updateMetadata(
        id,
        title: 'pride_FINAL(2)',
        author: '',
        useDefaultCover: false,
      );
      final b = await row(id);
      expect((b.originalTitle, b.originalAuthor), (null, null));
      expect(b.author, isNull);
    });

    test('clearing the author saves null, original author is kept', () async {
      final repo = BookRepository(db);
      final id = await add('T');
      await (db.update(db.books)..where((b) => b.id.equals(id))).write(
        const BooksCompanion(author: Value('Orig')),
      );
      await repo.updateMetadata(
        id,
        title: 'T',
        author: '  ',
        useDefaultCover: false,
      );
      final b = await row(id);
      expect(b.author, isNull);
      expect(b.originalAuthor, 'Orig');
    });

    test('empty title is rejected', () async {
      final id = await add('T');
      expect(
        () =>
            BookRepository(db)
                .updateMetadata(id, title: '  ', useDefaultCover: false),
        throwsArgumentError,
      );
    });

    test(
      'useDefaultCover hides the cover everywhere but keeps the raw name',
      () async {
        final repo = BookRepository(db);
        final id = await addWithAuthor();
        expect((await repo.watchShelf().first).single.coverName, 'c.jpg');
        await repo.updateMetadata(id, title: 'T', useDefaultCover: true);
        expect((await repo.watchShelf().first).single.coverName, isNull);
        expect((await repo.book(id))!.coverName, isNull);
        expect((await repo.bookEnd(id))!.coverName, isNull);
        final dir = Directory.systemTemp.createTempSync();
        addTearDown(() => dir.deleteSync(recursive: true));
        final info = await repo.bookInfo(id, FileStorage(dir));
        expect(info!.epubCoverName, 'c.jpg');
        expect(info.useDefaultCover, isTrue);
      },
    );
  });
}
