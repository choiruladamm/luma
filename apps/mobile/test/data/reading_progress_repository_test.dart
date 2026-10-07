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
    await repo.save(bookId, (
      chapterId: ch1,
      paragraphIndex: 4,
      paragraphOffset: 0.0,
    ));
    await repo.save(bookId, (
      chapterId: ch2,
      paragraphIndex: 9,
      paragraphOffset: 0.0,
    ));
    expect(await repo.load(bookId), (
      chapterId: ch2,
      paragraphIndex: 9,
      paragraphOffset: 0.0,
    ));
    expect(await db.select(db.readingProgress).get(), hasLength(1));
  });

  test('markOpened stamps lastOpenedAt; firstOpenedAt only once', () async {
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    await repo.markOpened(bookId);
    final first = await db.select(db.books).getSingle();
    expect(first.lastOpenedAt!.isAfter(before), isTrue);
    expect(first.firstOpenedAt, first.lastOpenedAt);

    final earlier = DateTime(2026, 1, 1);
    await db
        .update(db.books)
        .write(BooksCompanion(firstOpenedAt: Value(earlier)));
    await repo.markOpened(bookId);
    final again = await db.select(db.books).getSingle();
    expect(again.firstOpenedAt, earlier);
  });

  test(
    'offset is a fraction: kept as is inside 0..1, clamped outside',
    () async {
      Future<double> roundTrip(double offset) async {
        await repo.save(bookId, (
          chapterId: ch1,
          paragraphIndex: 2,
          paragraphOffset: offset,
        ));
        return (await repo.load(bookId))!.paragraphOffset;
      }

      expect(await roundTrip(0.37), 0.37);
      expect(await roundTrip(1.7), 1.0);
      expect(await roundTrip(-0.5), 0.0);
      expect(await roundTrip(double.nan), 0.0);

      // A bad value already in the database is clamped on the way out too.
      await db
          .update(db.readingProgress)
          .write(const ReadingProgressCompanion(paragraphOffset: Value(3)));
      expect((await repo.load(bookId))!.paragraphOffset, 1.0);
    },
  );

  final t0 = DateTime(2026, 10, 7, 9);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));
  ReadingSpan span(int chapterId, int from, int to) =>
      (chapterId: chapterId, startChar: from, endChar: to);
  Future<List<ReadingSession>> sessions() => (db.select(
    db.readingSessions,
  )..orderBy([(s) => OrderingTerm.asc(s.id)])).get();

  test('addReadingTime adds up', () async {
    await repo.addReadingTime(bookId, 90, at: at(90));
    await repo.addReadingTime(bookId, 30, at: at(200));
    final book = await db.select(db.books).getSingle();
    expect(book.readingSeconds, 120);
    expect(await sessions(), isEmpty); // no span, no session
  });

  test('a span becomes a session that ends at `at`', () async {
    await repo.addReadingTime(bookId, 60, at: at(60), span: span(ch1, 10, 40));
    final s = (await sessions()).single;
    expect(s.bookId, bookId);
    expect(s.chapterId, ch1);
    expect(s.startedAt, at(0));
    expect(s.seconds, 60);
    expect([s.startChar, s.endChar], [10, 40]);
  });

  test('a chunk that continues the last one merges into it', () async {
    await repo.addReadingTime(bookId, 60, at: at(60), span: span(ch1, 10, 40));
    await repo.addReadingTime(bookId, 30, at: at(100), span: span(ch1, 40, 55));
    final s = (await sessions()).single;
    expect(s.startedAt, at(0));
    expect(s.seconds, 90);
    expect([s.startChar, s.endChar], [10, 55]);
    // Total and sessions never disagree.
    final book = await db.select(db.books).getSingle();
    expect(book.readingSeconds, 90);
  });

  test('a new row when the chunk does not continue the last one', () async {
    Future<void> second(int seconds, int atSec, ReadingSpan sp) async {
      await repo.addReadingTime(
        bookId,
        60,
        at: at(60),
        span: span(ch1, 10, 40),
      );
      await repo.addReadingTime(bookId, seconds, at: at(atSec), span: sp);
      expect(await sessions(), hasLength(2));
      await db.delete(db.readingSessions).go();
    }

    await second(30, 100, span(ch2, 40, 55)); // other chapter
    await second(30, 100, span(ch1, 200, 210)); // jumped
    await second(30, 210, span(ch1, 40, 55)); // 2 min idle gap in between
  });

  test('a session stops growing at 5 minutes', () async {
    await repo.addReadingTime(bookId, 300, at: at(300), span: span(ch1, 0, 90));
    await repo.addReadingTime(bookId, 30, at: at(330), span: span(ch1, 90, 99));
    expect(await sessions(), hasLength(2));
  });

  test('deleting a book takes its sessions along', () async {
    await repo.addReadingTime(bookId, 60, at: at(60), span: span(ch1, 10, 40));
    await db.delete(db.books).go();
    expect(await sessions(), isEmpty);
  });
}
