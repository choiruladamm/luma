import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/reading_stats.dart';
import '../database/app_database.dart';

/// The numbers at the top of the Stats screen.
class ReadingSummary {
  const ReadingSummary({
    required this.weekSeconds,
    required this.totalSeconds,
    required this.finishedBooks,
  });

  /// Reading time this week, which starts on Monday ([weekStart]).
  final int weekSeconds;
  final int totalSeconds;
  final int finishedBooks;

  /// Nothing to show yet: no reading session and no finished book.
  bool get isEmpty => totalSeconds == 0 && finishedBooks == 0;
}

/// Reading habits from the recent sessions (rules in domain/reading_stats.dart).
class HabitStats {
  const HabitStats({
    required this.thisWeek,
    required this.lastWeek,
    required this.streak,
    required this.perDay,
    required this.perHour,
    required this.perWeekday,
  });

  final int thisWeek, lastWeek, streak;

  /// Seconds per local day over the last [StatsRepository.calendarWeeks].
  final Map<DateTime, int> perDay;

  /// Seconds per hour (0..23) and per weekday (Monday first) over the same span.
  final List<int> perHour, perWeekday;
}

/// Statistics read straight from Drift (docs/data-model.md, Storage map), so
/// they work offline and include books read with an own AI key.
class StatsRepository {
  StatsRepository(this._db, {this._clock = DateTime.now});

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Weeks shown on the reading calendar, the span of [watchHabits].
  static const calendarWeeks = 18;

  /// Emits the summary again whenever a session is saved or a book finishes.
  Stream<ReadingSummary> watchSummary() => _db
      .customSelect(
        '''
        SELECT
          COALESCE(SUM(CASE WHEN started_at >= ?1 THEN seconds END), 0) AS week_seconds,
          COALESCE(SUM(seconds), 0) AS total_seconds,
          (SELECT COUNT(*) FROM books WHERE finished_at IS NOT NULL) AS finished
        FROM reading_sessions
        ''',
        variables: [Variable.withDateTime(weekStart(_clock()))],
        readsFrom: {_db.readingSessions, _db.books},
      )
      .watchSingle()
      .map(
        (r) => ReadingSummary(
          weekSeconds: r.read<int>('week_seconds'),
          totalSeconds: r.read<int>('total_seconds'),
          finishedBooks: r.read<int>('finished'),
        ),
      );

  /// Emits the habits again whenever a session is saved: the sessions of the
  /// last [calendarWeeks] weeks, plus every reading day for the streak, which
  /// can be longer than that.
  Stream<HabitStats> watchHabits() {
    final now = _clock();
    final start = weekStart(now);
    final since = DateTime(
      start.year,
      start.month,
      start.day - 7 * (calendarWeeks - 1),
    );
    return (_db.select(
      _db.readingSessions,
    )..where((s) => s.startedAt.isBiggerOrEqualValue(since))).watch().asyncMap((
      rows,
    ) async {
      final slices = [
        for (final r in rows)
          (
            startedAt: r.startedAt,
            seconds: r.seconds,
            startChar: r.startChar,
            endChar: r.endChar,
          ),
      ];
      final days = await _db
          .customSelect(
            "SELECT DISTINCT date(started_at, 'unixepoch', 'localtime') AS d "
            'FROM reading_sessions',
          )
          .map((r) => DateTime.parse(r.read<String>('d')))
          .get();
      final week = weekSeconds(slices, now);
      return HabitStats(
        thisWeek: week.thisWeek,
        lastWeek: week.lastWeek,
        streak: streak(days, now),
        perDay: secondsPerDay(slices),
        perHour: secondsPerHour(slices),
        perWeekday: secondsPerWeekday(slices),
      );
    });
  }
}

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => StatsRepository(ref.watch(appDatabaseProvider)),
);

/// The Stats summary, also shown on the Atur tile.
final readingSummaryProvider = StreamProvider.autoDispose<ReadingSummary>(
  (ref) => ref.watch(statsRepositoryProvider).watchSummary(),
);

/// The habit cards on the Stats screen.
final habitStatsProvider = StreamProvider.autoDispose<HabitStats>(
  (ref) => ref.watch(statsRepositoryProvider).watchHabits(),
);
