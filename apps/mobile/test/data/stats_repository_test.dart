import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/stats_repository.dart';
import 'package:luma/domain/models/ai_reply.dart';
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

  test(
    'books: position, speed, time left, finished, latest read first',
    () async {
      await db
          .into(db.readingSessions)
          .insert(
            ReadingSessionsCompanion.insert(
              bookId: 1,
              chapterId: 1,
              startedAt: day(18),
              seconds: 1,
              startChar: 0,
              endChar: 20,
            ),
          );
      await db
          .into(db.readingSessions)
          .insert(
            ReadingSessionsCompanion.insert(
              bookId: 1,
              chapterId: 1,
              startedAt: day(19),
              seconds: 1,
              startChar: 20,
              endChar: 40,
            ),
          );
      await db
          .into(db.chapters)
          .insert(
            ChaptersCompanion.insert(
              id: const Value(2),
              bookId: 2,
              sortOrder: 0,
              charOffset: 0,
              title: 'I',
            ),
          );
      await db
          .into(db.readingSessions)
          .insert(
            ReadingSessionsCompanion.insert(
              bookId: 2,
              chapterId: 2,
              startedAt: day(20),
              seconds: 2,
              startChar: 0,
              endChar: 100,
            ),
          );
      await (db.update(db.books)..where((b) => b.id.equals(2))).write(
        BooksCompanion(finishedAt: Value(day(20))),
      );

      final books = await repo().watchBooks().first;

      expect([for (final b in books) b.bookId], [2, 1]);
      final open = books[1];
      expect(open.progress, 0.4);
      // 40 chars in 2 s = 1,200 chars/min; 60 chars left = 3 s.
      expect(open.charsPerMinute, 1200);
      expect(open.remaining, const Duration(seconds: 3));
      expect(open.finishedAt, isNull);
      expect(books[0].finishedAt, day(20));
      expect(books[0].remaining, isNull);
    },
  );

  test('costs per month, feature, and book; unreported stays null', () async {
    Future<void> call(
      DateTime at,
      AiCallKind kind,
      int? bookId,
      double? cost,
    ) => db
        .into(db.aiCalls)
        .insert(
          AiCallsCompanion.insert(
            bookId: Value(bookId),
            kind: kind,
            model: 'm',
            promptVersion: 1,
            chars: 10,
            costUsd: Value(cost),
            createdAt: Value(at),
          ),
        );
    await call(day(20), AiCallKind.group, 1, 0.25);
    await call(day(19), AiCallKind.group, 1, 0.5);
    await call(day(18), AiCallKind.chat, 2, null);
    await call(DateTime(2026, 10, 5), AiCallKind.breakdown, null, 0.125);
    // Older than the 6 months on the card.
    await call(DateTime(2026, 4, 30), AiCallKind.group, 1, 1);

    final c = await repo().watchCosts().first;

    expect(
      [for (final r in c.months) (r.key, r.calls, r.costUsd)],
      [('2026-11', 3, 0.75), ('2026-10', 1, 0.125)],
    );
    expect(
      [for (final r in c.features) (r.key, r.calls, r.costUsd)],
      [('group', 3, 1.75), ('chat', 1, null), ('breakdown', 1, 0.125)],
    );
    expect(
      [for (final r in c.books) (r.key, r.costUsd)],
      [('Book 1', 1.75), (null, 0.125), ('Book 2', null)],
    );
  });
}
