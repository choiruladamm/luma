import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/book_repository.dart';
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
}
