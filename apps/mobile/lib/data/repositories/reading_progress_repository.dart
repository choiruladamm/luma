import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/book.dart';
import '../../domain/reading.dart';
import '../database/app_database.dart';

/// Reading position: a chapter (stable id), a paragraph index within it, and
/// the fraction (0..1) of that paragraph already scrolled past the top line.
typedef ReadingPosition = ({
  int chapterId,
  int paragraphIndex,
  double paragraphOffset,
});

/// The chapter plus the absolute book positions (in characters) at the start
/// and end of one slice of reading time.
typedef ReadingSpan = ({int chapterId, int startChar, int endChar});

double _clampOffset(double offset) => offset.isNaN ? 0 : offset.clamp(0.0, 1.0);

class ReadingProgressRepository {
  ReadingProgressRepository(this._db);

  final AppDatabase _db;

  Future<ReadingPosition?> load(int bookId) async {
    final row = await (_db.select(
      _db.readingProgress,
    )..where((p) => p.bookId.equals(bookId))).getSingleOrNull();
    return row == null
        ? null
        : (
            chapterId: row.chapterId,
            paragraphIndex: row.paragraphIndex,
            paragraphOffset: _clampOffset(row.paragraphOffset),
          );
  }

  Future<void> save(int bookId, ReadingPosition position) => _db
      .into(_db.readingProgress)
      .insertOnConflictUpdate(
        ReadingProgressCompanion.insert(
          bookId: Value(bookId),
          chapterId: position.chapterId,
          paragraphIndex: position.paragraphIndex,
          paragraphOffset: Value(_clampOffset(position.paragraphOffset)),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Marks the book as opened: it moves to the front of the shelf and loses
  /// its "Baru" sticker. The first-opened time is recorded only once.
  Future<void> markOpened(int bookId) {
    final now = Variable(DateTime.now());
    return (_db.update(_db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion.custom(
        lastOpenedAt: now,
        firstOpenedAt: coalesce([_db.books.firstOpenedAt, now]),
      ),
    );
  }

  /// Records that the end-of-book screen was reached, once; rereading doesn't
  /// overwrite it. Markdown books are skipped because the last existing
  /// chapter isn't necessarily the end of the book.
  Future<void> markFinished(int bookId) =>
      (_db.update(_db.books)..where(
            (b) =>
                b.id.equals(bookId) &
                b.finishedAt.isNull() &
                b.sourceType.equalsValue(SourceType.markdown).not(),
          ))
          .write(BooksCompanion(finishedAt: Value(DateTime.now())));

  /// Longest merged session slice, so the heatmap hours and "jam favorit" stay
  /// counted per hour instead of all landing on the start hour.
  static const _maxMerged = Duration(minutes: 5);

  /// Adds active reading time to the book total and, when [span] is given,
  /// records the slice in `reading_sessions`.
  ///
  /// [at] is the end of the slice; it started [seconds] earlier. Both writes
  /// share one transaction so the total and the sessions never disagree. A
  /// slice that continues the last session (same chapter, starts where that
  /// session stopped, gap under [ReadingClock.idle]) is merged into its row.
  Future<void> addReadingTime(
    int bookId,
    int seconds, {
    required DateTime at,
    ReadingSpan? span,
  }) => _db.transaction(() async {
    await (_db.update(_db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion.custom(
        readingSeconds: _db.books.readingSeconds + Variable(seconds),
      ),
    );
    if (span == null) return;
    final startedAt = at.subtract(Duration(seconds: seconds));
    final last =
        await (_db.select(_db.readingSessions)
              ..where((s) => s.bookId.equals(bookId))
              ..orderBy([(s) => OrderingTerm.desc(s.id)])
              ..limit(1))
            .getSingleOrNull();
    if (last != null &&
        last.chapterId == span.chapterId &&
        last.endChar == span.startChar &&
        last.seconds < _maxMerged.inSeconds &&
        startedAt.difference(
              last.startedAt.add(Duration(seconds: last.seconds)),
            ) <
            ReadingClock.idle) {
      await (_db.update(
        _db.readingSessions,
      )..where((s) => s.id.equals(last.id))).write(
        ReadingSessionsCompanion(
          seconds: Value(last.seconds + seconds),
          endChar: Value(span.endChar),
        ),
      );
      return;
    }
    await _db
        .into(_db.readingSessions)
        .insert(
          ReadingSessionsCompanion.insert(
            bookId: bookId,
            chapterId: span.chapterId,
            startedAt: startedAt,
            seconds: seconds,
            startChar: span.startChar,
            endChar: span.endChar,
          ),
        );
  });
}

final readingProgressRepositoryProvider = Provider<ReadingProgressRepository>(
  (ref) => ReadingProgressRepository(ref.watch(appDatabaseProvider)),
);
