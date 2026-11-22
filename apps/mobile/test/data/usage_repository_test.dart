import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/repositories/usage_repository.dart';
import 'package:luma/data/services/backend_client.dart';
import 'package:luma/data/services/usage_service.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book.dart';

import '../support/backend_fakes.dart';

void main() {
  late AppDatabase db;
  late FakeAdapter adapter;
  late SettingsRepository settings;
  late DateTime now;
  String? token;

  // Local noon, so "yesterday" and the logged days don't depend on the zone.
  DateTime day(int d, [int hour = 12]) => DateTime(2026, 11, d, hour);

  UsageRepository repo() => UsageRepository(
    db: db,
    service: UsageService(
      BackendClient(
        baseUrl: 'https://luma.test',
        dio: Dio()..httpClientAdapter = adapter,
        sleep: (_) async {},
      ),
    ),
    settings: settings,
    token: () async => token,
    clock: () => now,
  );

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    adapter = FakeAdapter();
    settings = SettingsRepository(db);
    now = day(13);
    token = 'tok';
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            id: const Value(1),
            sourceType: SourceType.epub,
            title: 'Meditations',
            hash: const Value('3539482a'),
            parserVersion: 1,
            totalChars: 100,
          ),
        );
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            id: const Value(2),
            sourceType: SourceType.markdown,
            title: 'Catatan',
            bookKey: const Value('catatan'),
            parserVersion: 1,
            totalChars: 100,
          ),
        );
    await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            id: const Value(1),
            bookId: 1,
            sortOrder: 0,
            charOffset: 0,
            title: 'I',
          ),
        );
  });
  tearDown(() => db.close());

  Future<void> call(
    DateTime at, {
    int? bookId = 1,
    AiCallKind kind = AiCallKind.group,
    String? error,
    int? prompt = 100,
    double? cost,
    AiKeySource? source = AiKeySource.subsidy,
  }) => db
      .into(db.aiCalls)
      .insert(
        AiCallsCompanion.insert(
          bookId: Value(bookId),
          kind: kind,
          model: 'm',
          promptVersion: 1,
          chars: 10,
          promptTokens: Value(prompt),
          completionTokens: Value(prompt == null ? null : 10),
          costUsd: Value(cost),
          error: Value(error),
          createdAt: Value(at),
          keySource: Value(source),
        ),
      );

  Future<void> read(DateTime at, int seconds) => db
      .into(db.readingSessions)
      .insert(
        ReadingSessionsCompanion.insert(
          bookId: 1,
          chapterId: 1,
          startedAt: at,
          seconds: seconds,
          startChar: 0,
          endChar: 10,
        ),
      );

  List<Map<String, Object?>> sent() => [
    for (final r in adapter.requests)
      ...((r.data as Map)['rows'] as List).cast<Map<String, Object?>>(),
  ];

  test('rolls up per day, feature, model, book, and key source', () async {
    await call(day(11, 9), cost: 0.001);
    await call(day(11, 20), error: 'timeout', prompt: null, cost: 0.002);
    await call(day(11), bookId: null, kind: AiCallKind.chat, source: null);
    await call(day(12), bookId: 2, kind: AiCallKind.breakdown);
    await read(day(11, 8), 60);
    await read(day(11, 22), 30);
    await call(day(13)); // today: not complete yet

    final rows = await repo().rollup(through: '2026-11-12');

    expect(
      [for (final r in rows) r.toJson()],
      [
        {
          'day': '2026-11-11',
          'feature': 'chat',
          'model': 'm',
          'book_key': '',
          'book_title': null,
          'key_source': '',
          'calls': 1,
          'failed': 0,
          'prompt_tokens': 100,
          'completion_tokens': 10,
          'cost_usd': null,
          'reading_seconds': 0,
        },
        {
          'day': '2026-11-11',
          'feature': 'group',
          'model': 'm',
          'book_key': '3539482a',
          'book_title': 'Meditations',
          'key_source': 'subsidy',
          'calls': 2,
          'failed': 1,
          'prompt_tokens': 100,
          'completion_tokens': 10,
          'cost_usd': 0.003,
          'reading_seconds': 0,
        },
        {
          'day': '2026-11-11',
          'feature': 'reading',
          'model': '',
          'book_key': '3539482a',
          'book_title': 'Meditations',
          'key_source': '',
          'calls': 0,
          'failed': 0,
          'prompt_tokens': 0,
          'completion_tokens': 0,
          'cost_usd': null,
          'reading_seconds': 90,
        },
        {
          'day': '2026-11-12',
          'feature': 'breakdown',
          'model': 'm',
          'book_key': 'md:catatan',
          'book_title': 'Catatan',
          'key_source': 'subsidy',
          'calls': 1,
          'failed': 0,
          'prompt_tokens': 100,
          'completion_tokens': 10,
          'cost_usd': null,
          'reading_seconds': 0,
        },
      ],
    );
    expect(await repo().rollup(after: '2026-11-11', through: '2026-11-12'), [
      isA<UsageRow>().having((r) => r.day, 'day', '2026-11-12'),
    ]);
  });

  test('sends unsent days up to yesterday, once a day', () async {
    await call(day(11));
    await call(day(12));
    await call(day(13));
    adapter.queue.add(json(200, {'applied': 2}));

    expect(await repo().sendIfDue(), isTrue);
    expect([for (final r in sent()) r['day']], ['2026-11-11', '2026-11-12']);
    expect(adapter.requests.single.headers['authorization'], 'Bearer tok');
    expect(await settings.usageSentThrough(), '2026-11-12');

    // Same day again: nothing to send.
    expect(await repo().sendIfDue(), isFalse);
    // Next day: only the day that just completed.
    now = day(14);
    adapter.queue.add(json(200, {'applied': 1}));
    expect(await repo().sendIfDue(), isTrue);
    expect(sent().last['day'], '2026-11-13');
    expect(adapter.requests, hasLength(2));
  });

  test('a failure waits for a later day, then resends', () async {
    await call(day(12));
    adapter.queue.add(DioExceptionType.connectionError);
    adapter.queue.add(DioExceptionType.connectionError);
    adapter.queue.add(DioExceptionType.connectionError);

    expect(await repo().sendIfDue(), isFalse);
    expect(await settings.usageSentThrough(), isNull);
    final attempts = adapter.requests.length;
    expect(await repo().sendIfDue(), isFalse);
    expect(adapter.requests, hasLength(attempts));

    now = day(14);
    adapter.queue.add(json(200, {'applied': 1}));
    expect(await repo().sendIfDue(), isTrue);
    expect(sent().last['day'], '2026-11-12');
    expect(await settings.usageSentThrough(), '2026-11-13');
  });

  test('a stopped backlog keeps the complete days it sent', () async {
    for (var i = 0; i < UsageService.maxRows; i++) {
      await call(day(10), bookId: null, kind: AiCallKind.chat, prompt: i);
      await db.customStatement(
        "UPDATE ai_calls SET model = 'm$i' WHERE id = (SELECT max(id) FROM ai_calls)",
      );
    }
    await call(day(11));
    adapter.queue
      ..add(json(200, {'applied': 500}))
      ..add(
        json(
          429,
          {
            'error': {
              'code': 'QUOTA_EXCEEDED',
              'message': 'Daily usage quota reached',
            },
          },
          headers: {'retry-after': '3600'},
        ),
      );

    expect(await repo().sendIfDue(), isFalse);
    expect(await settings.usageSentThrough(), '2026-11-10');
  });

  test('signed out: no request', () async {
    await call(day(12));
    token = null;
    expect(await repo().sendIfDue(), isFalse);
    expect(adapter.requests, isEmpty);
    expect(await settings.usageAttemptedOn(), isNull);
  });
}
