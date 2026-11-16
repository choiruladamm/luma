import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/ai_key_repository.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/data/services/ai_key_service.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/data/services/session_store.dart';

import '../support/backend_fakes.dart';

void main() {
  late FakeAdapter adapter;
  late SessionStore session;
  late ApiKeyStore byok;
  late DateTime now;
  late AiKeyRepository repo;

  /// Respons `POST /v1/ai/key` dengan key & kedaluwarsa tertentu.
  ResponseBody issued(String key, DateTime expiresAt) => json(200, {
    'key': key,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'dailyLimitUsd': 0.02,
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    adapter = FakeAdapter();
    session = SessionStore();
    byok = ApiKeyStore();
    // Jauh sebelum tanggal `<iso>` fixture kontrak (2026-11-12), supaya key
    // dari fixture masih segar.
    now = DateTime.utc(2026, 10, 1, 15);
    final client = BackendClient(
      baseUrl: 'https://luma.test',
      dio: Dio()..httpClientAdapter = adapter,
      sleep: (_) async {},
    );
    repo = AiKeyRepository(byok, session, AiKeyService(client), now: () => now);
  });

  test('BYOK wins and never calls the backend', () async {
    await byok.write('sk-or-v1-punya-sendiri');
    await session.writeToken('tok');

    expect(await repo.read(), 'sk-or-v1-punya-sendiri');
    expect(adapter.requests, isEmpty);
  });

  test('no session and no BYOK → null (UI shows "no key")', () async {
    expect(await repo.read(), isNull);
    expect(adapter.requests, isEmpty);
  });

  test(
    'fetches the subsidy key once, then serves it from storage (contract)',
    () async {
      await session.writeToken('tok');
      adapter.queue.add(fromContract(contract('ai-key')));

      final first = await repo.read();
      final second = await repo.read();

      expect(first, 'tok123.sig456');
      expect(second, first);
      expect(adapter.requests, hasLength(1));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/v1/ai/key');
      expect(req.headers['authorization'], 'Bearer tok');
      expect(req.data, isEmpty);
    },
  );

  test('parallel reads share one backend call', () async {
    await session.writeToken('tok');
    adapter.queue.add(issued('sk-1', now.add(const Duration(days: 30))));

    final keys = await Future.wait([repo.read(), repo.read(), repo.read()]);

    expect(keys, ['sk-1', 'sk-1', 'sk-1']);
    expect(adapter.requests, hasLength(1));
  });

  test(
    'a key rejected by OpenRouter is rotated on the next read (contract)',
    () async {
      await session.writeToken('tok');
      adapter.queue
        ..add(issued('sk-1', now.add(const Duration(days: 30))))
        ..add(fromContract(contract('ai-key-rotate')));
      final first = await repo.read();

      repo.markRejected(first!);
      final next = await repo.read();

      expect(next, 'tok123.sig456');
      expect(adapter.requests.last.data, {'rotate': true});
      expect(await repo.read(), next);
      expect(adapter.requests, hasLength(2));
    },
  );

  test('refreshes a key that expires within a day', () async {
    await session.writeToken('tok');
    await session.writeSubsidyKey(
      SubsidyKey(key: 'sk-lama', expiresAt: now.add(const Duration(hours: 12))),
    );
    adapter.queue.add(issued('sk-baru', now.add(const Duration(days: 30))));

    expect(await repo.read(), 'sk-baru');
    expect(adapter.requests.single.data, isEmpty);
  });

  test('offline: keeps using a stored key that has not expired yet', () async {
    await session.writeToken('tok');
    await session.writeSubsidyKey(
      SubsidyKey(key: 'sk-lama', expiresAt: now.add(const Duration(hours: 12))),
    );
    adapter.queue.addAll(List.filled(3, DioExceptionType.connectionError));

    expect(await repo.read(), 'sk-lama');
  });

  test(
    'offline with an expired key → network error, not "add a key"',
    () async {
      await session.writeToken('tok');
      await session.writeSubsidyKey(
        SubsidyKey(
          key: 'sk-mati',
          expiresAt: now.subtract(const Duration(minutes: 1)),
        ),
      );
      adapter.queue.addAll(List.filled(3, DioExceptionType.connectionError));

      await expectLater(
        repo.read(),
        throwsA(
          isA<AiException>().having((e) => e.error, 'error', AiError.network),
        ),
      );
    },
  );

  test('banned account → AI_BANNED error, no retry loop (contract)', () async {
    await session.writeToken('tok');
    adapter.queue.add(fromContract(contract('error-ai-banned')));

    await expectLater(
      repo.read(),
      throwsA(
        isA<AiException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.detail, 'detail', aiBannedCode),
      ),
    );
    expect(adapter.requests, hasLength(1));
  });

  group('subsidyFailureOf', () {
    test('402 is "quota used up" only on the subsidy key', () {
      const e = AiException(AiError.http, status: 402);
      expect(subsidyFailureOf(e, usingSubsidy: true), SubsidyFailure.exhausted);
      expect(subsidyFailureOf(e, usingSubsidy: false), isNull);
    });

    test('AI_BANNED is "revoked" either way; other errors are not quota', () {
      const banned = AiException(
        AiError.http,
        status: 403,
        detail: aiBannedCode,
      );
      expect(
        subsidyFailureOf(banned, usingSubsidy: false),
        SubsidyFailure.banned,
      );
      expect(
        subsidyFailureOf(
          const AiException(AiError.http, status: 401),
          usingSubsidy: true,
        ),
        isNull,
      );
      expect(
        subsidyFailureOf(
          const AiException(AiError.network),
          usingSubsidy: true,
        ),
        isNull,
      );
      expect(subsidyFailureOf('boom', usingSubsidy: true), isNull);
    });
  });

  test('isSubsidy tells the subsidy key apart from BYOK', () async {
    await session.writeToken('tok');
    adapter.queue.add(issued('sk-1', now.add(const Duration(days: 30))));
    final key = await repo.read();

    expect(await repo.isSubsidy(key!), isTrue);
    expect(await repo.isSubsidy('sk-or-v1-punya-sendiri'), isFalse);
  });

  test('write stores BYOK; logout drops the subsidy key', () async {
    await session.writeToken('tok');
    adapter.queue.add(issued('sk-1', now.add(const Duration(days: 30))));
    await repo.read();

    await session.clearToken();

    expect(await session.readSubsidyKey(), isNull);
    await repo.write('sk-or-v1-baru');
    expect(await byok.read(), 'sk-or-v1-baru');
  });

  group('AiKeyService (contract)', () {
    test('usage and config parse the backend responses', () async {
      final service = AiKeyService(
        BackendClient(
          baseUrl: 'https://luma.test',
          dio: Dio()..httpClientAdapter = adapter,
        ),
      );
      adapter.queue
        ..add(fromContract(contract('ai-usage')))
        ..add(fromContract(contract('ai-config')));

      final usage = await service.usage('tok');
      final config = await service.config('tok');

      expect(usage.remainingUsd, 0.015);
      expect(usage.usedTodayUsd, 0.005);
      expect(usage.resetsAt.isUtc, isTrue);
      expect(config.chatModels, contains('deepseek/deepseek-v4.1-flash'));
      expect(config.embeddingModels, hasLength(2));
      expect(adapter.requests.map((r) => r.uri.path), [
        '/v1/ai/usage',
        '/v1/ai/config',
      ]);
    });
  });
}
