import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ai_prompt.dart';
import '../../domain/models/ai_reply.dart';
import '../../domain/models/book.dart';
import '../database/app_database.dart';

/// Size of the translation cache, shown in Pengaturan.
typedef AiCacheStats = ({int paragraphs, int bytes});

/// Caches LLM results (`ai_results`).
class AiResultsRepository {
  AiResultsRepository(this._db);

  final AppDatabase _db;

  /// Counts paragraphs that already have a translation, with their approximate text size.
  Stream<AiCacheStats> watchStats() => _db
      .customSelect(
        'SELECT '
        '(SELECT COUNT(*) FROM paragraphs p JOIN ai_results a '
        'ON a.chapter_id = p.chapter_id AND a.group_index = p.group_index) '
        'AS n, '
        '(SELECT COALESCE(SUM(LENGTH(CAST(translations AS BLOB)) + '
        'LENGTH(CAST(meaning AS BLOB))), 0) FROM ai_results) AS bytes',
        readsFrom: {_db.paragraphs, _db.aiResults},
      )
      .watchSingle()
      .map((r) => (paragraphs: r.read<int>('n'), bytes: r.read<int>('bytes')));

  /// Returns the groups in this chapter that already have a translation (margin markers).
  Stream<Set<int>> watchGroups(int chapterId) =>
      (_db.selectOnly(_db.aiResults)
            ..addColumns([_db.aiResults.groupIndex])
            ..where(_db.aiResults.chapterId.equals(chapterId)))
          .watch()
          .map(
            (rows) => {for (final r in rows) r.read(_db.aiResults.groupIndex)!},
          );

  /// Returns the cached result, or null. A result from an older prompt version
  /// ([aiPromptVersion]) counts as missing so it is translated again.
  Future<AiReply?> find(GroupRef group) async {
    final row =
        await (_db.select(_db.aiResults)..where(
              (a) =>
                  a.chapterId.equals(group.chapterId) &
                  a.groupIndex.equals(group.groupIndex) &
                  a.promptVersion.isBiggerOrEqualValue(aiPromptVersion),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return AiReply(
      translations: (jsonDecode(row.translations) as List).cast<String>(),
      meaning: row.meaning,
    );
  }

  /// Saving counts as the first open (`openCount` 1). Overwriting a result from an
  /// older prompt version restarts the count at 1.
  Future<void> save(GroupRef group, AiReply reply, {required String model}) =>
      _db
          .into(_db.aiResults)
          .insertOnConflictUpdate(
            AiResultsCompanion.insert(
              chapterId: group.chapterId,
              groupIndex: group.groupIndex,
              translations: jsonEncode(reply.translations),
              meaning: reply.meaning,
              model: model,
              promptVersion: const Value(aiPromptVersion),
              openCount: const Value(1),
              lastOpenedAt: Value(DateTime.now()),
            ),
          );

  /// Records that the Artinya sheet opened from cache: the group was read once more.
  Future<void> markOpened(GroupRef group) =>
      (_db.update(_db.aiResults)..where(
            (a) =>
                a.chapterId.equals(group.chapterId) &
                a.groupIndex.equals(group.groupIndex),
          ))
          .write(
            AiResultsCompanion.custom(
              openCount: _db.aiResults.openCount + const Constant(1),
              lastOpenedAt: Variable(DateTime.now()),
            ),
          );

  /// Returns the text sent to the LLM: book and chapter, the group's paragraphs (in
  /// order), and up to [contextCount] paragraphs before the group's first paragraph
  /// in the same chapter.
  Future<({AiBook? book, List<String> target, List<String> context})>
  promptText(GroupRef group, {int contextCount = 3}) async {
    final target =
        await (_db.select(_db.paragraphs)
              ..where(
                (p) =>
                    p.chapterId.equals(group.chapterId) &
                    p.groupIndex.equals(group.groupIndex),
              )
              ..orderBy([(p) => OrderingTerm.asc(p.paragraphIndex)]))
            .get();
    if (target.isEmpty) {
      return (book: null, target: <String>[], context: <String>[]);
    }
    final source = await (_db.select(_db.chapters).join([
      innerJoin(_db.books, _db.books.id.equalsExp(_db.chapters.bookId)),
    ])..where(_db.chapters.id.equals(group.chapterId))).getSingleOrNull();
    final before =
        await (_db.select(_db.paragraphs)
              ..where(
                (p) =>
                    p.chapterId.equals(group.chapterId) &
                    p.paragraphIndex.isSmallerThanValue(
                      target.first.paragraphIndex,
                    ) &
                    p.type.equalsValue(ParagraphType.paragraph),
              )
              ..orderBy([(p) => OrderingTerm.desc(p.paragraphIndex)])
              ..limit(contextCount))
            .get();
    return (
      book: source == null
          ? null
          : (
              title: source.readTable(_db.books).title,
              author: source.readTable(_db.books).author,
              chapter: source.readTable(_db.chapters).title,
            ),
      target: [for (final p in target) p.content],
      context: [for (final p in before.reversed) p.content],
    );
  }

  /// Deletes every translation; groups opened later call the LLM again.
  Future<void> clear() => _db.delete(_db.aiResults).go();
}

final aiResultsRepositoryProvider = Provider<AiResultsRepository>(
  (ref) => AiResultsRepository(ref.watch(appDatabaseProvider)),
);

final aiCacheStatsProvider = StreamProvider.autoDispose<AiCacheStats>(
  (ref) => ref.watch(aiResultsRepositoryProvider).watchStats(),
);
