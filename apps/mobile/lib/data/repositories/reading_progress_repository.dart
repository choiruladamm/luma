import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/book.dart';
import '../../domain/reading.dart';
import '../database/app_database.dart';

/// Posisi baca: chapter (id stabil) + indeks paragraf di chapter itu + bagian
/// paragraf itu yang udah lewat garis atas (0..1).
typedef ReadingPosition = ({
  int chapterId,
  int paragraphIndex,
  double paragraphOffset,
});

/// Bab + posisi absolut di buku (karakter) di awal dan akhir satu potongan
/// waktu baca.
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

  /// Buku dibuka: naik ke depan rak, stiker "Baru" ilang. Pertama kali
  /// dibuka dicatet sekali.
  Future<void> markOpened(int bookId) {
    final now = Variable(DateTime.now());
    return (_db.update(_db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion.custom(
        lastOpenedAt: now,
        firstOpenedAt: coalesce([_db.books.firstOpenedAt, now]),
      ),
    );
  }

  /// Layar akhir buku kebuka: dicatet sekali, baca ulang gak nimpa. Buku
  /// Markdown dilewat: bab terakhir yang ada belum tentu akhir buku.
  Future<void> markFinished(int bookId) =>
      (_db.update(_db.books)..where(
            (b) =>
                b.id.equals(bookId) &
                b.finishedAt.isNull() &
                b.sourceType.equalsValue(SourceType.epub),
          ))
          .write(BooksCompanion(finishedAt: Value(DateTime.now())));

  /// Potongan sesi yang digabung paling lama segini, biar jam di heatmap dan
  /// "jam favorit" tetep kehitung per jam (bukan semua ke jam mulai baca).
  static const _maxMerged = Duration(minutes: 5);

  /// Nambahin waktu baca aktif ke total buku, dan (kalau [span] ada) nyatet
  /// potongan sesinya di `reading_sessions`. [at] = akhir potongan; awalnya
  /// [seconds] sebelum itu. Satu transaksi, jadi total dan sesi gak beda.
  ///
  /// Potongan yang nyambung sama sesi terakhir (bab sama, mulai di mana sesi
  /// itu berhenti, jeda < [ReadingClock.idle]) digabung ke barisnya.
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
