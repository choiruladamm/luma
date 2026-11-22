import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';

/// The numbers at the top of the Stats screen.
class ReadingSummary {
  const ReadingSummary({
    required this.weekSeconds,
    required this.weekDays,
    required this.totalSeconds,
    required this.finishedBooks,
  });

  /// Reading time over the last 7 local days, today included.
  final int weekSeconds;

  /// Local days with any reading among those 7.
  final int weekDays;
  final int totalSeconds;
  final int finishedBooks;

  /// Nothing to show yet: no reading session and no finished book.
  bool get isEmpty => totalSeconds == 0 && finishedBooks == 0;
}

/// Statistics read straight from Drift (docs/data-model.md, Storage map), so
/// they work offline and include books read with an own AI key.
class StatsRepository {
  StatsRepository(this._db, {this._clock = DateTime.now});

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Emits the summary again whenever a session is saved or a book finishes.
  Stream<ReadingSummary> watchSummary() {
    final now = _clock();
    final weekStart = DateTime(now.year, now.month, now.day - 6);
    return _db
        .customSelect(
          '''
          SELECT
            COALESCE(SUM(CASE WHEN started_at >= ?1 THEN seconds END), 0) AS week_seconds,
            COUNT(DISTINCT CASE WHEN started_at >= ?1
              THEN date(started_at, 'unixepoch', 'localtime') END) AS week_days,
            COALESCE(SUM(seconds), 0) AS total_seconds,
            (SELECT COUNT(*) FROM books WHERE finished_at IS NOT NULL) AS finished
          FROM reading_sessions
          ''',
          variables: [Variable.withDateTime(weekStart)],
          readsFrom: {_db.readingSessions, _db.books},
        )
        .watchSingle()
        .map(
          (r) => ReadingSummary(
            weekSeconds: r.read<int>('week_seconds'),
            weekDays: r.read<int>('week_days'),
            totalSeconds: r.read<int>('total_seconds'),
            finishedBooks: r.read<int>('finished'),
          ),
        );
  }
}

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => StatsRepository(ref.watch(appDatabaseProvider)),
);

/// The Stats summary, also shown on the Atur tile.
final readingSummaryProvider = StreamProvider.autoDispose<ReadingSummary>(
  (ref) => ref.watch(statsRepositoryProvider).watchSummary(),
);
