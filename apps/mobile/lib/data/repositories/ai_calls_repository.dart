import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chat_budget.dart';
import '../../domain/models/ai_reply.dart';
import '../database/app_database.dart';
import 'ai_key_repository.dart';

/// Writes the `ai_calls` log: one row per AI call that reached OpenRouter
/// (docs/data-model.md). Cache hits and cancelled calls are never recorded.
class AiCallsRepository {
  AiCallsRepository(this._db, this._isSubsidy);

  final AppDatabase _db;
  final Future<bool> Function(String apiKey) _isSubsidy;

  /// Records one call. Without a key nothing was sent, so nothing is written.
  /// [bookId] defaults to the book of [group]'s chapter.
  Future<void> record({
    required AiCallKind kind,
    required String model,
    required int promptVersion,
    required int chars,
    required String? apiKey,
    required int totalMs,
    int? firstTokenMs,
    ChatUsage? usage,
    GroupRef? group,
    int? bookId,
    AiError? error,
  }) async {
    if (apiKey == null || apiKey.trim().isEmpty || error == AiError.noApiKey) {
      return;
    }
    final chapterId = group?.chapterId;
    bookId ??= chapterId == null
        ? null
        : (await (_db.select(
            _db.chapters,
          )..where((c) => c.id.equals(chapterId))).getSingleOrNull())?.bookId;
    final source = await _isSubsidy(apiKey)
        ? AiKeySource.subsidy
        : AiKeySource.own;
    await _db
        .into(_db.aiCalls)
        .insert(
          AiCallsCompanion.insert(
            bookId: Value(bookId),
            chapterId: Value(chapterId),
            groupIndex: Value(group?.groupIndex),
            kind: kind,
            model: model,
            promptVersion: promptVersion,
            chars: chars,
            promptTokens: Value(usage?.promptTokens),
            completionTokens: Value(usage?.completionTokens),
            costUsd: Value(usage?.cost),
            firstTokenMs: Value(firstTokenMs),
            totalMs: Value(totalMs),
            error: Value(error?.name),
            keySource: Value(source),
          ),
        );
  }
}

final aiCallsRepositoryProvider = Provider<AiCallsRepository>(
  (ref) => AiCallsRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(aiKeyRepositoryProvider).isSubsidy,
  ),
);
