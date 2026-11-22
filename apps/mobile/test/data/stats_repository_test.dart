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

  // 2026-11-20 is a Friday; its week starts Monday the 16th.
  StatsRepository repo() => StatsRepository(db, clock: () => day(20));

  test('empty before any reading', () async {
    final s = await repo().watchSummary().first;
    expect(s.isEmpty, isTrue);
    expect(s.weekSeconds, 0);
  });

  test('sums this week (from Monday) apart from all time', () async {
    await read(day(20, 8), 600); // today
    await read(day(16, 0), 120); // Monday, first moment of the week
    await read(day(15, 23), 900); // Sunday before: last week
    await (db.update(db.books)..where((b) => b.id.equals(2))).write(
      BooksCompanion(finishedAt: Value(day(10))),
    );

    final s = await repo().watchSummary().first;

    expect(s.weekSeconds, 720);
    expect(s.totalSeconds, 1620);
    expect(s.finishedBooks, 1);
    expect(s.isEmpty, isFalse);
  });

  test(
    'habits: weeks, streak beyond the calendar, per day, hour, weekday',
    () async {
      await read(day(20, 21), 300); // Friday 21h
      await read(day(19, 21), 200); // Thursday 21h
      await read(day(18, 7), 100); // Wednesday 7h
      await read(day(12, 21), 50); // last week's Thursday
      // Outside the 18-week calendar, but still part of an older streak.
      await read(DateTime(2026, 6, 1, 12), 999);

      final h = await repo().watchHabits().first;

      expect((h.thisWeek, h.lastWeek), (600, 50));
      expect(h.streak, 3);
      expect(h.perDay[DateTime(2026, 11, 20)], 300);
      expect(h.perDay.containsKey(DateTime(2026, 6)), isFalse);
      expect(h.perHour[21], 550);
      expect(h.perWeekday, [0, 0, 100, 250, 300, 0, 0]);
    },
  );

  test('emits again when a session is saved', () async {
    final emitted = repo().watchSummary().map((s) => s.totalSeconds);
    final expectation = expectLater(emitted, emitsInOrder([0, 60]));
    await Future<void>.delayed(Duration.zero);
    await read(day(20), 60);
    await expectation;
  });
}
