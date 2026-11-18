import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/breakdown_prompt.dart';
import '../../domain/models/breakdown.dart';
import '../../domain/models/ai_reply.dart';
import '../database/app_database.dart';
import 'ai_results_repository.dart';

/// Caches Bedahin results (`ai_breakdowns`) and gathers the inputs for its prompt.
class AiBreakdownsRepository {
  AiBreakdownsRepository(this._db, this._results);

  final AppDatabase _db;
  final AiResultsRepository _results;

  /// Returns everything sent to Bedahin for [group], or null when the group has no
  /// translation and meaning yet (Bedahin opens only after the quick meaning finishes).
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

  /// Returns the cached raw reply, or null. A reply from an older prompt version or
  /// for a replaced translation (different [sourceHash]) counts as missing.
  Future<String?> find(GroupRef group, String sourceHash) async {
    final row = await _row(group);
    return row?.sourceHash == sourceHash ? row!.body : null;
  }

  /// Returns how many breakdown parts are still valid for this group's current
  /// translation; 0 means none yet (drives the "Buka bedahan · N bagian" entry in
  /// the Artinya sheet).
  Future<int> sections(GroupRef group) async {
    final row = await _row(group);
    if (row == null) return 0;
    final current =
        await (_db.select(_db.aiResults)..where(
              (a) =>
                  a.chapterId.equals(group.chapterId) &
                  a.groupIndex.equals(group.groupIndex),
            ))
            .getSingleOrNull();
    final valid =
        current != null &&
        breakdownSourceHash(
              (jsonDecode(current.translations) as List).cast<String>(),
            ) ==
            row.sourceHash;
    // Only replies that passed `parseBreakdown` are stored: one marker per part.
    return valid ? '[BAGIAN'.allMatches(row.body).length : 0;
  }

  /// Returns the destination of a Nyambung card from group [from]: with [chapter]
  /// (`B<n>`, 1-based, in `sortOrder`) the first group of that chapter, without it
  /// the next group in the same chapter. Null when the destination doesn't exist
  /// (the card renders as plain text).
  Future<BreakdownPeek?> peek(GroupRef from, int? chapter) async {
    GroupRef? target;
    if (chapter == null) {
      target = (chapterId: from.chapterId, groupIndex: from.groupIndex + 1);
    } else {
      final current = await (_db.select(
        _db.chapters,
      )..where((c) => c.id.equals(from.chapterId))).getSingleOrNull();
      if (current == null) return null;
      final chapters =
          await (_db.select(_db.chapters)
                ..where((c) => c.bookId.equals(current.bookId))
                ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
              .get();
      if (chapter < 1 || chapter > chapters.length) return null;
      final id = chapters[chapter - 1].id;
      final first =
          await (_db.select(_db.paragraphs)
                ..where(
                  (p) => p.chapterId.equals(id) & p.groupIndex.isNotNull(),
                )
                ..orderBy([(p) => OrderingTerm.asc(p.paragraphIndex)])
                ..limit(1))
              .getSingleOrNull();
      if (first == null) return null;
      target = (chapterId: id, groupIndex: first.groupIndex!);
    }
    final paragraphs =
        await (_db.select(_db.paragraphs)
              ..where(
                (p) =>
                    p.chapterId.equals(target!.chapterId) &
                    p.groupIndex.equals(target.groupIndex),
              )
              ..orderBy([(p) => OrderingTerm.asc(p.paragraphIndex)]))
            .get();
    if (paragraphs.isEmpty) return null;
    return BreakdownPeek(
      group: target,
      original: [for (final p in paragraphs) p.content],
      translations: (await _results.find(target))?.translations,
    );
  }

  /// Stores or overwrites a result that passed `parseBreakdown`.
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

  /// Backs "Hapus cache" in Pengaturan.
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
