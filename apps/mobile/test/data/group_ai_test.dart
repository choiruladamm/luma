import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/ai_results_repository.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/models/ai_model.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/ui/features/reader/view_models/reader_view_model.dart';

import '../fakes.dart';

void main() {
  late AppDatabase db;
  late FakeOpenRouter ai;
  late ProviderContainer container;
  late int chapter;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'openrouter_api_key': 'sk'});
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    ai = FakeOpenRouter();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        openRouterServiceProvider.overrideWithValue(ai),
      ],
    );
    final book = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            sourceType: SourceType.epub,
            title: 'Walden',
            parserVersion: 1,
            totalChars: 1,
          ),
        );
    chapter = await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            bookId: book,
            sortOrder: 0,
            title: 'I',
            charOffset: 0,
          ),
        );
    // p0..p4 alone, heading h5, group 5 = p6 + p7.
    final rows = [
      for (var i = 0; i < 5; i++) (i, i as int?, ParagraphType.paragraph),
      (5, null, ParagraphType.heading),
      (6, 5, ParagraphType.paragraph),
      (7, 5, ParagraphType.paragraph),
    ];
    for (final (i, g, type) in rows) {
      await db
          .into(db.paragraphs)
          .insert(
            ParagraphsCompanion.insert(
              chapterId: chapter,
              paragraphIndex: i,
              groupIndex: Value(g),
              type: type,
              content: type == ParagraphType.heading ? 'h$i' : 'p$i',
            ),
          );
    }
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  GroupRef group(int g) => (chapterId: chapter, groupIndex: g);

  test('asks the LLM once, then serves the cache', () async {
    final first = await container.read(groupAiProvider(group(5)).future);
    expect(first.translations, ['id: p6', 'id: p7']);
    expect(ai.calls, hasLength(1));
    // Group paragraphs in order; the 3 paragraphs before, skipping headings.
    expect(ai.calls.single.target, ['p6', 'p7']);
    expect(ai.calls.single.context, ['p2', 'p3', 'p4']);
    expect(ai.calls.single.model, defaultAiModel);
    expect(ai.calls.single.apiKey, 'sk');

    // Tapped again later: fresh provider, same answer, no new request.
    container.invalidate(groupAiProvider(group(5)));
    final again = await container.read(groupAiProvider(group(5)).future);
    expect(again.translations, first.translations);
    expect(again.meaning, first.meaning);
    expect(ai.calls, hasLength(1));

    final row = await db.select(db.aiResults).getSingle();
    expect(row.model, defaultAiModel);
  });

  test('two taps while loading share one request', () async {
    final a = container.read(groupAiProvider(group(5)).future);
    final b = container.read(groupAiProvider(group(5)).future);
    await Future.wait([a, b]);
    expect(ai.calls, hasLength(1));
  });

  test('the first group gets no context', () async {
    await container.read(groupAiProvider(group(0)).future);
    expect(ai.calls.single.context, isEmpty);
  });

  test('a failure is not cached and not retried on its own', () async {
    ai.failure = const AiException(AiError.timeout);
    final sub = container.listen(groupAiProvider(group(1)), (_, _) {});
    addTearDown(sub.close);
    await expectLater(
      container.read(groupAiProvider(group(1)).future),
      throwsA(isA<AiException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(ai.calls, hasLength(1)); // no automatic retry
    expect(await AiResultsRepository(db).find(group(1)), isNull);

    ai.failure = null;
    container.invalidate(groupAiProvider(group(1)));
    final ok = await container.read(groupAiProvider(group(1)).future);
    expect(ok.translations, ['id: p1']);
    expect(ai.calls, hasLength(2));
  });

  test('no API key: the LLM is not asked to do anything', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await expectLater(
      container.read(groupAiProvider(group(5)).future),
      throwsA(
        isA<AiException>().having((e) => e.error, 'error', AiError.noApiKey),
      ),
    );
    expect(await db.select(db.aiResults).get(), isEmpty);
  });
}
