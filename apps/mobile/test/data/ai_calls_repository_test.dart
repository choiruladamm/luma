import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/ai_calls_repository.dart';
import 'package:luma/domain/models/ai_reply.dart';

void main() {
  late AppDatabase db;
  setUp(
    () => db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    ),
  );
  tearDown(() => db.close());

  Future<void> record(AiCallsRepository repo, String? key, [AiError? error]) =>
      repo.record(
        kind: AiCallKind.chat,
        model: 'm',
        promptVersion: 1,
        chars: 3,
        apiKey: key,
        totalMs: 10,
        error: error,
      );

  test('the key source is recorded; without a key nothing is', () async {
    final repo = AiCallsRepository(db, (key) async => key == 'subsidy');
    await record(repo, 'subsidy');
    await record(repo, 'own', AiError.http);
    await record(repo, null);
    await record(repo, 'own', AiError.noApiKey);
    final rows = await db.select(db.aiCalls).get();
    expect(
      [for (final r in rows) (r.keySource, r.error)],
      [(AiKeySource.subsidy, null), (AiKeySource.own, 'http')],
    );
    expect(rows.first.bookId, isNull);
    expect(rows.first.promptTokens, isNull);
  });
}
