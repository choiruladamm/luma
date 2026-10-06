import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/reading_progress_repository.dart';
import 'package:luma/domain/models/book.dart';

void main() {
  late AppDatabase db;
  late ReadingProgressRepository repo;
  late int bookId, ch1, ch2;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = ReadingProgressRepository(db);
    bookId = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            sourceType: SourceType.epub,
            title: 'Meditations',
            parserVersion: 1,
            totalChars: 10,
          ),
        );
    Future<int> chapter(int order) => db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            bookId: bookId,
            sortOrder: order,
            title: 'Book $order',
            charOffset: order * 5,
          ),
        );
    ch1 = await chapter(0);
    ch2 = await chapter(1);
  });
  tearDown(() => db.close());

  test('nothing saved yet → null', () async {
    expect(await repo.load(bookId), isNull);
  });

  test('save overwrites the one row per book', () async {
    await repo.save(bookId, (chapterId: ch1, paragraphIndex: 4));
    await repo.save(bookId, (chapterId: ch2, paragraphIndex: 9));
    expect(await repo.load(bookId), (chapterId: ch2, paragraphIndex: 9));
    expect(await db.select(db.readingProgress).get(), hasLength(1));
  });

  test('markOpened stamps lastOpenedAt', () async {
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    await repo.markOpened(bookId);
    final book = await db.select(db.books).getSingle();
    expect(book.lastOpenedAt!.isAfter(before), isTrue);
  });
}
