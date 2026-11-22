import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/stats_repository.dart';
import 'package:luma/domain/models/book.dart';

void main() {
  late AppDatabase db;
  // Local noon, so the 7-day window doesn't depend on the zone.
  DateTime day(int d, [int hour = 12]) => DateTime(2026, 11, d, hour);

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    for (final id in [1, 2]) {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              id: Value(id),
              sourceType: SourceType.epub,
              title: 'Book $id',
              hash: Value('h$id'),
              parserVersion: 1,
              totalChars: 100,
            ),
          );
    }
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            id: const Value(1),
            bookId: 1,
            sortOrder: 0,
            charOffset: 0,
            title: 'I',
          ),
        );
  });
  tearDown(() => db.close());

  Future<void> read(DateTime at, int seconds) => db
      .into(db.readingSessions)
      .insert(
        ReadingSessionsCompanion.insert(
          bookId: 1,
          chapterId: 1,
          startedAt: at,
          seconds: seconds,
          startChar: 0,
          endChar: 10,
        ),
      );

  StatsRepository repo() => StatsRepository(db, clock: () => day(20));

  test('empty before any reading', () async {
    final s = await repo().watchSummary().first;
    expect(s.isEmpty, isTrue);
    expect((s.weekSeconds, s.weekDays), (0, 0));
  });

  test('sums the last 7 local days apart from all time', () async {
    await read(day(20, 8), 600); // today
    await read(day(20, 21), 300); // today again: still one day
    await read(day(14, 0), 120); // first day of the window
    await read(day(13, 23), 900); // just outside it
    await (db.update(db.books)..where((b) => b.id.equals(2))).write(
      BooksCompanion(finishedAt: Value(day(10))),
    );

    final s = await repo().watchSummary().first;

    expect(s.weekSeconds, 1020);
    expect(s.weekDays, 2);
    expect(s.totalSeconds, 1920);
    expect(s.finishedBooks, 1);
    expect(s.isEmpty, isFalse);
  });

  test('emits again when a session is saved', () async {
    final emitted = repo().watchSummary().map((s) => s.totalSeconds);
    final expectation = expectLater(emitted, emitsInOrder([0, 60]));
    await Future<void>.delayed(Duration.zero);
    await read(day(20), 60);
    await expectation;
  });
}
