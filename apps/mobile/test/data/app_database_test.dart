import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
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

  Future<int> insertBook({String hash = 'abc'}) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          sourceType: SourceType.epub,
          title: 'Pride and Prejudice',
          author: const Value('Jane Austen'),
          fileName: Value('$hash.epub'),
          hash: Value(hash),
          parserVersion: 1,
          totalChars: 120,
        ),
      );

  Future<int> insertChapter(int bookId, int sortOrder) => db
      .into(db.chapters)
      .insert(
        ChaptersCompanion.insert(
          bookId: bookId,
          sortOrder: sortOrder,
          title: 'Chapter $sortOrder',
          charOffset: sortOrder * 60,
        ),
      );

  test('book → chapters → paragraphs round-trip in display order', () async {
    final bookId = await insertBook();
    // Inserted out of order: display order comes from sortOrder, not id.
    final second = await insertChapter(bookId, 1);
    final first = await insertChapter(bookId, 0);
    await db.batch(
      (b) => b.insertAll(db.paragraphs, [
        ParagraphsCompanion.insert(
          chapterId: first,
          paragraphIndex: 0,
          type: ParagraphType.heading,
          content: 'Chapter I',
        ),
        ParagraphsCompanion.insert(
          chapterId: first,
          paragraphIndex: 1,
          groupIndex: const Value(0),
          type: ParagraphType.paragraph,
          content: 'It is a truth universally acknowledged…',
        ),
      ]),
    );

    final chapters =
        await (db.select(db.chapters)
              ..where((c) => c.bookId.equals(bookId))
              ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
            .get();
    expect(chapters.map((c) => c.id), [first, second]);

    final paras =
        await (db.select(db.paragraphs)
              ..where((p) => p.chapterId.equals(first))
              ..orderBy([(p) => OrderingTerm.asc(p.paragraphIndex)]))
            .get();
    expect(paras.map((p) => p.type), [
      ParagraphType.heading,
      ParagraphType.paragraph,
    ]);
    expect(paras.first.groupIndex, isNull);
    expect(paras.last.groupIndex, 0);

    final book = await db.select(db.books).getSingle();
    expect(book.fileName, 'abc.epub');
    expect(book.lastOpenedAt, isNull);
  });

  test('same hash cannot be imported twice', () async {
    await insertBook();
    await expectLater(insertBook(), throwsA(isA<SqliteException>()));
  });

  test('same paragraph index in a chapter is rejected', () async {
    final chapterId = await insertChapter(await insertBook(), 0);
    final p = ParagraphsCompanion.insert(
      chapterId: chapterId,
      paragraphIndex: 0,
      type: ParagraphType.paragraph,
      content: 'x',
    );
    await db.into(db.paragraphs).insert(p);
    await expectLater(
      db.into(db.paragraphs).insert(p),
      throwsA(isA<SqliteException>()),
    );
  });

  test('deleting a book cascades to its chapters and paragraphs', () async {
    final keep = await insertBook(hash: 'keep');
    final gone = await insertBook(hash: 'gone');
    for (final bookId in [keep, gone]) {
      final chapterId = await insertChapter(bookId, 0);
      await db
          .into(db.paragraphs)
          .insert(
            ParagraphsCompanion.insert(
              chapterId: chapterId,
              paragraphIndex: 0,
              type: ParagraphType.paragraph,
              content: 'x',
            ),
          );
    }

    await (db.delete(db.books)..where((b) => b.id.equals(gone))).go();

    final chapters = await db.select(db.chapters).get();
    expect(chapters.map((c) => c.bookId), [keep]);
    final paras = await db.select(db.paragraphs).get();
    expect(paras.map((p) => p.chapterId), [chapters.single.id]);
  });
}
