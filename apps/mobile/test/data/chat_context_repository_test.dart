import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/chat_context_repository.dart';
import 'package:luma/data/repositories/chat_repository.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/chat_prompt.dart';
import 'package:luma/domain/chat_retrieval.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/models/book_chat.dart';

import 'openrouter_service_test.dart' show json, sse, event;

class Keys extends ApiKeyStore {
  String? key = 'first-key';
  int reads = 0;
  @override
  Future<String?> read() async {
    reads++;
    return key;
  }
}

class ChatAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final embeddingModels = <String>[];
  int? embeddingStatus;
  DioExceptionType? embeddingError;
  bool failQueryOnly = false;
  bool clarification = false;
  bool emptySelection = false;
  bool badRewrite = false;
  String answerId = 'S1';
  Future<void> Function()? onSelect;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = options.data as Map;
    if (options.path == '/embeddings') {
      final model = data['model'] as String;
      embeddingModels.add(model);
      if (model == ChatEmbeddingModel.qwen8b.id) {
        if (embeddingError != null) {
          throw DioException(requestOptions: options, type: embeddingError!);
        }
        if (embeddingStatus != null &&
            (!failQueryOnly ||
                ((data['input'] as List).first as String).startsWith(
                  chatQueryPrefix,
                ))) {
          return json({'error': 'provider failed'}, embeddingStatus!);
        }
      }
      final count = model == ChatEmbeddingModel.qwen8b.id ? 4096 : 3072;
      final input = data['input'] as List;
      return json({
        'model': model,
        'data': [
          for (var i = input.length - 1; i >= 0; i--)
            {
              'index': i,
              'embedding': List.generate(count, (j) => j == i % 2 ? 1 : 0),
            },
        ],
      });
    }
    final messages = data['messages'] as List;
    final system = (messages.first as Map)['content'];
    String raw;
    if (system == chatRewriteSystem) {
      raw = badRewrite
          ? 'invalid'
          : jsonEncode({
              'query': 'Who keeps the garden?',
              'needs_clarification': clarification,
            });
    } else if (system == chatSelectionSystem) {
      await onSelect?.call();
      raw = jsonEncode({
        'resolved_question': 'Who keeps it?',
        'selected': emptySelection ? [] : [1, 2],
      });
    } else {
      raw = jsonEncode({
        'status': 'answered',
        'claims': [
          {
            'text': 'Penjaganya 🌿.',
            'source_ids': [answerId],
          },
        ],
        'note': '',
      });
    }
    return sse([
      for (final rune in raw.runes) event(String.fromCharCode(rune)),
      'data: [DONE]\n\n',
    ]);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AppDatabase db;
  late ChatRepository chat;
  late ChatContextRepository context;
  late ChatAdapter adapter;
  late Keys keys;
  late ChatBookRef book, other;
  late int chapter;
  late ChatTurn turn;
  const model = 'chosen/model';
  const text = 'A garden belongs to its keeper.';

  Future<int> addBook(String title) => db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          sourceType: SourceType.epub,
          title: title,
          parserVersion: 1,
          totalChars: 100,
        ),
      );
  Future<int> addChapter(int bookId, int order, String content) async {
    final id = await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            bookId: bookId,
            sortOrder: order,
            title: 'Chapter $order',
            charOffset: order * 100,
          ),
        );
    await db
        .into(db.paragraphs)
        .insert(
          ParagraphsCompanion.insert(
            chapterId: id,
            paragraphIndex: 0,
            type: ParagraphType.paragraph,
            content: content,
            groupIndex: const Value(0),
          ),
        );
    return id;
  }

  Future<ChatTurn> first() => chat.createFirstTurn(
    book,
    question: 'Siapa yang punya taman?',
    model: model,
    promptVersion: chatPromptVersion,
  );
  ChatSource source() => ChatSource(
    id: 'S1',
    chapterTitle: 'Chapter 0',
    anchors: [
      SourceAnchor(
        book: book,
        chapterId: chapter,
        paragraphIndex: 0,
        start: 0,
        end: text.length,
        paragraphHash: chatTextHash(text),
        snapshot: text,
      ),
    ],
  );
  Matcher fails(AiError error, [int? status]) => throwsA(
    isA<AiException>()
        .having((e) => e.error, 'error', error)
        .having((e) => e.status, 'status', status),
  );

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    chat = ChatRepository(db);
    adapter = ChatAdapter();
    keys = Keys();
    context = ChatContextRepository(
      db,
      chat,
      OpenRouterService(
        Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
          ..httpClientAdapter = adapter,
      ),
      keys,
    );
    await db
        .into(db.settings)
        .insert(SettingsCompanion.insert(key: 'ai.model', value: model));
    book = (bookId: await addBook('Garden'), contentRevision: 1);
    other = (bookId: await addBook('Other'), contentRevision: 1);
    chapter = await addChapter(book.bookId, 0, text);
    await addChapter(
      book.bookId,
      10,
      'Later in the book, the keeper plants roses.',
    );
    await addChapter(other.bookId, 0, 'FOREIGN SECRET');
    turn = await first();
  });
  tearDown(() async {
    context.dispose();
    chat.dispose();
    await db.close();
  });

  test('whole-book scoped retrieval -> frozen prompt -> validated stream -> persistence', () async {
    final prepared = (await context.prepare(turn))!;
    expect(prepared.model, model);
    expect(
      prepared.prompt.sources.map((s) => s.chapterTitle),
      contains('Chapter 10'),
    );
    expect(prepared.prompt.user, isNot(contains('FOREIGN SECRET')));
    expect(
      prepared.prompt.sources.every(
        (s) => s.anchors.every((a) => a.book == book),
      ),
      isTrue,
    );
    final stored = await db.select(db.chatTurns).getSingle();
    expect(stored.phase, 'waiting');
    expect(stored.sources, contains(text));
    final frames = await prepared.stream().toList();
    expect(
      frames.take(frames.length - 1).every((f) => f.answer == null),
      isTrue,
    );
    expect(frames.last.answer!.blocks.single.sources.single.text, text);
    expect(
      await chat.finalize(
        turn.attemptRef,
        phase: ChatPhase.done,
        draft: frames.last.draft,
        answer: frames.last.answer,
      ),
      isTrue,
    );
    expect(
      (await chat.watchTurns(book.bookId, turn.sessionId).first)
          .single
          .trustedHistory,
      isTrue,
    );
    await expectLater(prepared.stream().toList(), throwsStateError);
  });

  test(
    'eligible history only; key reread each send; document cache reused',
    () async {
      final s = source();
      await chat.prepareSources(turn.attemptRef, [s]);
      await chat.finalize(
        turn.attemptRef,
        phase: ChatPhase.done,
        answer: ChatAnswer(
          status: ChatAnswerStatus.answered,
          blocks: [
            ChatAnswerBlock(text: 'Penjaga taman.', sources: [s]),
          ],
        ),
      );
      final next = await chat.appendTurn(
        book,
        turn.sessionId,
        question: 'Dia nanam apa?',
        model: model,
        promptVersion: 1,
      );
      final firstPrepared = (await context.prepare(next))!;
      expect(firstPrepared.prompt.historyTurnIds, [turn.id]);
      await chat.finalize(next.attemptRef, phase: ChatPhase.stopped);
      keys.key = 'changed-key';
      final separate = await first();
      final secondPrepared = (await context.prepare(separate))!;
      expect(secondPrepared.prompt.historyTurnIds, isEmpty);
      expect(secondPrepared.prompt.user, isNot(contains('Penjaga taman.')));
      expect(keys.reads, 2);
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer changed-key',
      );
      final embeddings = adapter.requests
          .where((r) => r.path == '/embeddings')
          .toList();
      expect(
        embeddings,
        hasLength(3),
      ); // one document batch and two query batches
    },
  );

  test(
    'no key, stale revision and model mismatch stop before network',
    () async {
      keys.key = null;
      await expectLater(context.prepare(turn), fails(AiError.noApiKey));
      keys.key = 'key';
      await (db.update(db.settings)..where((s) => s.key.equals('ai.model')))
          .write(const SettingsCompanion(value: Value('changed')));
      await expectLater(context.prepare(turn), fails(AiError.invalidResponse));
      await (db.update(db.books)..where((b) => b.id.equals(book.bookId))).write(
        const BooksCompanion(contentRevision: Value(2)),
      );
      expect(await context.prepare(turn), isNull);
      expect(adapter.requests, isEmpty);
    },
  );

  test('clarification and empty valid selection skip answer, unlike rewrite failures', () async {
    adapter.clarification = true;
    var prepared = (await context.prepare(turn))!;
    expect(
      (await prepared.stream().single).answer!.status,
      ChatAnswerStatus.notFound,
    );
    expect(adapter.requests, hasLength(1));
    await chat.finalize(turn.attemptRef, phase: ChatPhase.stopped);
    turn = await first();
    adapter.clarification = false;
    adapter.badRewrite = true;
    await expectLater(context.prepare(turn), fails(AiError.invalidResponse));
    expect(adapter.requests, hasLength(2));
    adapter.badRewrite = false;
    adapter.emptySelection = true;
    prepared = (await context.prepare(turn))!;
    expect(
      (await prepared.stream().single).answer!.status,
      ChatAnswerStatus.notFound,
    );
    expect(
      adapter.requests.where(
        (r) =>
            ((r.data as Map)['messages'] as List?)?.first['content'] ==
            chatAnswerSystemPrompt,
      ),
      isEmpty,
    );
  });

  test(
    'Qwen provider fallback rebuilds all documents AND queries in Large space',
    () async {
      adapter.embeddingStatus = 503;
      final prepared = (await context.prepare(turn))!;
      expect(prepared.prompt.sources, isNotEmpty);
      expect(adapter.embeddingModels, [
        ChatEmbeddingModel.qwen8b.id,
        ChatEmbeddingModel.openaiLarge.id,
        ChatEmbeddingModel.openaiLarge.id,
      ]);
      final large = adapter.requests
          .where(
            (r) =>
                r.path == '/embeddings' &&
                (r.data as Map)['model'] == ChatEmbeddingModel.openaiLarge.id,
          )
          .toList();
      expect(((large.first.data as Map)['input'] as List), contains(text));
      expect(
        ((large.last.data as Map)['input'] as List).every(
          (s) => !(s as String).startsWith(chatQueryPrefix),
        ),
        isTrue,
      );
    },
  );

  for (final status in [400, 401, 402, 403]) {
    test(
      'embedding HTTP $status does not trigger provider fallback or not_found',
      () async {
        adapter.embeddingStatus = status;
        await expectLater(context.prepare(turn), fails(AiError.http, status));
        expect(adapter.embeddingModels, [ChatEmbeddingModel.qwen8b.id]);
      },
    );
  }
  for (final type in [
    DioExceptionType.cancel,
    DioExceptionType.badCertificate,
    DioExceptionType.unknown,
  ]) {
    test('embedding $type never triggers fallback', () async {
      adapter.embeddingError = type;
      await expectLater(context.prepare(turn), throwsA(isA<DioException>()));
      expect(adapter.embeddingModels, [ChatEmbeddingModel.qwen8b.id]);
    });
  }

  test(
    'deleted/stopped attempt after retrieval cannot freeze or stream',
    () async {
      adapter.onSelect = () async {
        await chat.deleteSession(book.bookId, turn.sessionId);
      };
      expect(await context.prepare(turn), isNull);
      expect(
        adapter.requests.where((r) => r.path == '/chat/completions'),
        hasLength(2),
      );
    },
  );
  test('content changed during retrieval rejects source freeze', () async {
    adapter.onSelect = () async {
      await (db.update(db.paragraphs)
            ..where((p) => p.chapterId.equals(chapter)))
          .write(const ParagraphsCompanion(content: Value('changed')));
    };
    await expectLater(context.prepare(turn), fails(AiError.invalidResponse));
    expect(
      adapter.requests.where((r) => r.path == '/chat/completions'),
      hasLength(2),
    );
  });
  test(
    'invalid citation never becomes a source action and is not retried',
    () async {
      final prepared = (await context.prepare(turn))!;
      adapter.answerId = 'S999';
      final frames = <ChatStreamFrame>[];
      await expectLater(
        prepared.stream().forEach(frames.add),
        fails(AiError.invalidResponse),
      );
      expect(frames.every((f) => f.answer == null), isTrue);
      expect(
        adapter.requests.where((r) => r.path == '/chat/completions'),
        hasLength(3),
      );
    },
  );
  test('cancel between preparation and stream sends no answer', () async {
    final prepared = (await context.prepare(turn))!;
    final cancel = CancelToken()..cancel();
    await expectLater(
      prepared.stream(cancel: cancel).toList(),
      throwsA(isA<DioException>()),
    );
    expect(
      adapter.requests.where((r) => r.path == '/chat/completions'),
      hasLength(2),
    );
  });
  test(
    'query failure after cached Qwen docs still fully rebuilds Large',
    () async {
      adapter.embeddingStatus = 429;
      adapter.failQueryOnly = true;
      expect(await context.prepare(turn), isNotNull);
      expect(adapter.embeddingModels, [
        ChatEmbeddingModel.qwen8b.id,
        ChatEmbeddingModel.qwen8b.id,
        ChatEmbeddingModel.openaiLarge.id,
        ChatEmbeddingModel.openaiLarge.id,
      ]);
    },
  );

  test(
    'quote is pinned and original excerpt, never translation, enters prompts',
    () async {
      await chat.finalize(turn.attemptRef, phase: ChatPhase.stopped);
      final quote = ChatQuote(
        anchors: source().anchors,
        translation: 'SECRET TRANSLATION',
      );
      final quoted = await chat.createFirstTurn(
        book,
        question: 'Tanyain ini',
        model: model,
        promptVersion: 1,
        quote: quote,
      );
      final prepared = (await context.prepare(quoted))!;
      expect(prepared.prompt.sources.first.text, text);
      final rewrite = adapter.requests.first.data as Map;
      final user = jsonDecode(
        (rewrite['messages'] as List).last['content'] as String,
      ) as Map;
      expect(user['selectedQuote'], text);
      expect(
        jsonEncode(adapter.requests.map((r) => r.data).toList()),
        isNot(contains('SECRET TRANSLATION')),
      );
      final selector = adapter.requests.last.data as Map;
      final selection = jsonDecode(
        (selector['messages'] as List).last['content'] as String,
      ) as Map;
      expect(selection['selectedSourceId'], 1);
    },
  );

  test(
    'oversized corpus is rejected before paid rewrite or embeddings',
    () async {
      await (db.update(db.paragraphs)
            ..where((p) => p.chapterId.equals(chapter)))
          .write(ParagraphsCompanion(content: Value('word ' * 310000)));
      await expectLater(context.prepare(turn), fails(AiError.invalidResponse));
      expect(adapter.requests, isEmpty);
    },
  );

  test('session deleted after prepare skips answer network', () async {
    final prepared = (await context.prepare(turn))!;
    await chat.deleteSession(book.bookId, turn.sessionId);
    expect(await prepared.stream().toList(), isEmpty);
    expect(
      adapter.requests.where((r) => r.path == '/chat/completions'),
      hasLength(2),
    );
  });

  test(
    'stopped attempt during answer never emits validated citations',
    () async {
      final prepared = (await context.prepare(turn))!;
      final frames = <ChatStreamFrame>[];
      await for (final frame in prepared.stream()) {
        frames.add(frame);
        if (frames.length == 1) {
          await chat.finalize(turn.attemptRef, phase: ChatPhase.stopped);
        }
      }
      expect(frames, isNotEmpty);
      expect(frames.every((f) => f.answer == null), isTrue);
    },
  );

  test('live hash changed during answer rejects final citation', () async {
    final prepared = (await context.prepare(turn))!;
    final frames = <ChatStreamFrame>[];
    await expectLater(
      prepared.stream().asyncMap((frame) async {
        frames.add(frame);
        if (frames.length == 1) {
          await (db.update(db.paragraphs)
                ..where((p) => p.chapterId.equals(chapter)))
              .write(const ParagraphsCompanion(content: Value('changed')));
        }
        return frame;
      }).toList(),
      fails(AiError.invalidResponse),
    );
    expect(frames.every((f) => f.answer == null), isTrue);
  });

  test('stale revision never reuses document cache', () async {
    expect(await context.prepare(turn), isNotNull);
    await (db.update(db.books)..where((b) => b.id.equals(book.bookId))).write(
      const BooksCompanion(contentRevision: Value(2)),
    );
    final current = (bookId: book.bookId, contentRevision: 2);
    final fresh = await chat.createFirstTurn(
      current,
      question: 'Siapa?',
      model: model,
      promptVersion: 1,
    );
    expect(await context.prepare(fresh), isNotNull);
    expect(adapter.embeddingModels, hasLength(4));
    expect(await context.prepare(turn), isNull);
  });
  test(
    'restart recovery prevents a persisted running turn from reaching network',
    () async {
      context.dispose();
      chat.dispose();
      chat = ChatRepository(db);
      context = ChatContextRepository(
        db,
        chat,
        OpenRouterService(
          Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
            ..httpClientAdapter = adapter,
        ),
        keys,
      );
      expect(await context.prepare(turn), isNull);
      expect(adapter.requests, isEmpty);
      expect((await db.select(db.chatTurns).getSingle()).phase, 'interrupted');
    },
  );
}
