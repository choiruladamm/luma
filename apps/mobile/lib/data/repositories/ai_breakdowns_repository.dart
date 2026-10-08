import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/breakdown_prompt.dart';
import '../../domain/models/ai_reply.dart';
import '../database/app_database.dart';
import 'ai_results_repository.dart';

/// Cache Bedahin (`ai_breakdowns`) + bahan prompt-nya.
class AiBreakdownsRepository {
  AiBreakdownsRepository(this._db, this._results);

  final AppDatabase _db;
  final AiResultsRepository _results;

  /// Semua yang dikirim ke Bedahin buat [group]. Null = grup ini belum punya
  /// terjemahan + makna (Bedahin cuma kebuka abis makna cepat selesai).
  Future<BreakdownInput?> input(GroupRef group) async {
    final reply = await _results.find(group);
    final text = await _results.promptText(group);
    final book = text.book;
    if (reply == null || book == null) return null;
    final chapter = await (_db.select(
      _db.chapters,
    )..where((c) => c.id.equals(group.chapterId))).getSingle();
    final chapters =
        await (_db.select(_db.chapters)
              ..where((c) => c.bookId.equals(chapter.bookId))
              ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
            .get();
    final next =
        await (_db.select(_db.paragraphs)
              ..where(
                (p) =>
                    p.chapterId.equals(group.chapterId) &
                    p.groupIndex.equals(group.groupIndex + 1),
              )
              ..orderBy([(p) => OrderingTerm.asc(p.paragraphIndex)]))
            .get();
    return BreakdownInput(
      book: book,
      chapters: [for (final c in chapters) c.title],
      chapter: chapters.indexWhere((c) => c.id == chapter.id) + 1,
      context: text.context,
      original: text.target,
      translations: reply.translations,
      meaning: reply.meaning,
      next: [for (final p in next) p.content],
    );
  }

  /// Balasan mentah yang ke-cache, atau null. Versi prompt lama atau
  /// terjemahan yang udah diganti ([sourceHash] beda) = dianggap belum ada.
  Future<String?> find(GroupRef group, String sourceHash) async {
    final row = await _row(group);
    return row?.sourceHash == sourceHash ? row!.body : null;
  }

  /// Ada bedahan yang masih berlaku buat terjemahan grup ini sekarang
  /// (entri "Buka bedahan" di sheet Artinya).
  Future<bool> exists(GroupRef group) async {
    final row = await _row(group);
    if (row == null) return false;
    final current =
        await (_db.select(_db.aiResults)..where(
              (a) =>
                  a.chapterId.equals(group.chapterId) &
                  a.groupIndex.equals(group.groupIndex),
            ))
            .getSingleOrNull();
    return current != null &&
        breakdownSourceHash(
              (jsonDecode(current.translations) as List).cast<String>(),
            ) ==
            row.sourceHash;
  }

  /// Simpan / timpa hasil yang udah lolos `parseBreakdown`.
  Future<void> save(
    GroupRef group, {
    required String body,
    required String sourceHash,
    required String model,
  }) => _db
      .into(_db.aiBreakdowns)
      .insertOnConflictUpdate(
        AiBreakdownsCompanion.insert(
          chapterId: group.chapterId,
          groupIndex: group.groupIndex,
          body: body,
          sourceHash: sourceHash,
          model: model,
          promptVersion: breakdownPromptVersion,
          createdAt: Value(DateTime.now()),
        ),
      );

  /// "Hapus cache" di Pengaturan.
  Future<void> clear() => _db.delete(_db.aiBreakdowns).go();

  Future<AiBreakdown?> _row(GroupRef group) =>
      (_db.select(_db.aiBreakdowns)..where(
            (b) =>
                b.chapterId.equals(group.chapterId) &
                b.groupIndex.equals(group.groupIndex) &
                b.promptVersion.isBiggerOrEqualValue(breakdownPromptVersion),
          ))
          .getSingleOrNull();
}

final aiBreakdownsRepositoryProvider = Provider<AiBreakdownsRepository>(
  (ref) => AiBreakdownsRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(aiResultsRepositoryProvider),
  ),
);
