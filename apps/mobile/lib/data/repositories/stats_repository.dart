import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/book.dart';
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

/// One book on the progress cards.
class BookStats {
  const BookStats({
    required this.bookId,
    required this.title,
    required this.progress,
    required this.charsPerMinute,
    required this.remaining,
    required this.finishedAt,
  });

  final int bookId;
  final String title;

  /// Position 0..1 from the latest session's end.
  final double progress;

  /// The book's own reading speed; null without measurable reading.
  final double? charsPerMinute;

  /// Time left at the book's recent speed; null when unknown (no recent
  /// speed, or a Markdown book, which has no end).
  final Duration? remaining;
  final DateTime? finishedAt;
}

/// AI calls and cost for one month, feature, or book on the cost card.
class CostRow {
  const CostRow({
    required this.key,
    required this.calls,
    required this.costUsd,
  });

  /// `YYYY-MM`, an `AiCallKind` name, or a book title (null for a deleted book).
  final String? key;
  final int calls;

  /// Null when no call in the row reported a cost ("gak tercatat", not zero).
  final double? costUsd;
}

/// The cost card: the last [StatsRepository.costMonths] months, newest first,
/// all-time per feature, and the most expensive books.
typedef CostStats = ({
  List<CostRow> months,
  List<CostRow> features,
  List<CostRow> books,
});

/// Statistics read straight from Drift (docs/data-model.md, Storage map), so
/// they work offline and include books read with an own AI key.
class StatsRepository {
  StatsRepository(this._db, {this._clock = DateTime.now});

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Months on the cost card.
  static const costMonths = 6;

  /// Books on the cost card.
  static const costBooks = 5;

  /// Emits the cost card again whenever an AI call is logged (`ai_calls`).
  Stream<CostStats> watchCosts() {
    final now = _clock();
    final since = DateTime(now.year, now.month - (costMonths - 1));
    Future<List<CostRow>> rows(String sql, [List<Variable> vars = const []]) =>
        _db
            .customSelect(sql, variables: vars)
            .map(
              (r) => CostRow(
                key: r.readNullable<String>('k'),
                calls: r.read<int>('calls'),
                costUsd: r.readNullable<double>('cost'),
              ),
            )
            .get();
    return _db
        .select(_db.aiCalls)
        .watch()
        .asyncMap(
          (_) async => (
            months: await rows(
              "SELECT strftime('%Y-%m', created_at, 'unixepoch', 'localtime') "
              'AS k, COUNT(*) AS calls, SUM(cost_usd) AS cost FROM ai_calls '
              'WHERE created_at >= ?1 GROUP BY k ORDER BY k DESC',
              [Variable.withDateTime(since)],
            ),
            features: await rows(
              'SELECT kind AS k, COUNT(*) AS calls, SUM(cost_usd) AS cost '
              'FROM ai_calls GROUP BY kind ORDER BY calls DESC',
            ),
            books: await rows(
              'SELECT b.title AS k, COUNT(*) AS calls, SUM(c.cost_usd) AS cost '
              'FROM ai_calls c LEFT JOIN books b ON b.id = c.book_id '
              'GROUP BY c.book_id '
              'ORDER BY COALESCE(SUM(c.cost_usd), 0) DESC, COUNT(*) DESC '
              'LIMIT $costBooks',
            ),
          ),
        );
  }

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

  /// Days of a book's sessions its time-left estimate reads speed from.
  static const recentDays = 30;

  /// Books with any reading session, latest read first, each with its
  /// position, speed, and time left (rules in domain/reading_stats.dart).
  Stream<List<BookStats>> watchBooks() {
    final now = _clock();
    final recentFrom = now.subtract(const Duration(days: recentDays));
    final query = _db.select(_db.readingSessions).join([
      innerJoin(_db.books, _db.books.id.equalsExp(_db.readingSessions.bookId)),
    ])..orderBy([OrderingTerm.asc(_db.readingSessions.startedAt)]);
    return query.watch().map((rows) {
      final books = <int, Book>{};
      final slices = <int, List<ReadingSlice>>{};
      for (final r in rows) {
        final book = r.readTable(_db.books);
        final s = r.readTable(_db.readingSessions);
        books[book.id] = book;
        (slices[book.id] ??= []).add((
          startedAt: s.startedAt,
          seconds: s.seconds,
          startChar: s.startChar,
          endChar: s.endChar,
        ));
      }
      final out = [
        for (final id in books.keys)
          _bookStats(books[id]!, slices[id]!, recentFrom),
      ];
      // Sessions come oldest first, so the last one is the latest read.
      int last(BookStats b) =>
          slices[b.bookId]!.last.startedAt.millisecondsSinceEpoch;
      return out..sort((a, b) => last(b).compareTo(last(a)));
    });
  }

  static BookStats _bookStats(
    Book book,
    List<ReadingSlice> slices,
    DateTime recentFrom,
  ) {
    final position = slices.last.endChar;
    final open =
        book.sourceType != SourceType.markdown && book.finishedAt == null;
    return BookStats(
      bookId: book.id,
      title: book.title,
      progress: book.totalChars <= 0
          ? 0
          : (position / book.totalChars).clamp(0, 1).toDouble(),
      charsPerMinute: charsPerMinuteOf(slices),
      remaining: open
          ? estimatedFinish(
              remainingChars: book.totalChars - position,
              recent: slices.where((s) => s.startedAt.isAfter(recentFrom)),
            )
          : null,
      finishedAt: book.finishedAt,
    );
  }

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

/// The progress cards on the Stats screen.
final bookStatsProvider = StreamProvider.autoDispose<List<BookStats>>(
  (ref) => ref.watch(statsRepositoryProvider).watchBooks(),
);

/// The cost card on the Stats screen.
final costStatsProvider = StreamProvider.autoDispose<CostStats>(
  (ref) => ref.watch(statsRepositoryProvider).watchCosts(),
);
