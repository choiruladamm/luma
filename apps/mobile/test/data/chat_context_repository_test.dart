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
import 'package:luma/domain/chat_exploration.dart';
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
  String strategy = 'specific';
  List<String> queries = [];
  List<String> missingQueries = [];
  final batches = <List<String>>[];
  int? badBatch;
  Future<void> Function()? onBatch;

  String answerId = 'S1';
  Future<void> Function()? onSelect;
  Future<void> Function()? onEmbedding;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = options.data as Map;
    if (options.path == '/embeddings') {
      await onEmbedding?.call();
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
              'strategy': strategy,
              'queries': queries,
            });
    } else if (system == chatGlobalSystem) {
      final user =
          jsonDecode((messages.last as Map)['content'] as String) as Map;
      final batch = (user['newWindowIds'] as List).cast<String>();
      batches.add(batch);
      await onBatch?.call();
      raw = jsonEncode({
        'notes': [
          {
            'text': 'Gagasan diperiksa.',
            'source_ids': [badBatch == batches.length ? 'S99999' : batch.first],
          },
        ],
      });
    } else if (system == chatSelectionSystem) {
      await onSelect?.call();
      raw = jsonEncode({
        'resolved_question': 'Who keeps it?',
        'selected': emptySelection ? [] : [1, 2],
        'missing_queries': missingQueries,
      });
    } else {
      final hasSources =
          ((jsonDecode((messages.last as Map)['content'] as String)
                      as Map)['sources']
                  as List)
              .isNotEmpty;
      raw = jsonEncode({
        'status': clarification
            ? 'clarify'
            : hasSources
            ? 'answered'
            : 'partial',
        'parts': [
          {
            'text': hasSources
                ? 'Penjaganya 🌿.'
                : 'Bukti buku belum ketemu. Bagian mana yang lo maksud?',
            'kind': hasSources ? 'book' : 'conversation',
            'source_ids': hasSources ? [answerId] : [],
          },
        ],
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

  int documentRequests() => adapter.requests
      .where(
        (r) =>
            r.path == '/embeddings' &&
            !(((r.data as Map)['input'] as List).first as String).startsWith(
              chatQueryPrefix,
            ),
      )
      .length;
  ChatContextRepository reopenContext() => ChatContextRepository(
    db,
    chat,
    OpenRouterService(
      Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
        ..httpClientAdapter = adapter,
    ),
    keys,
  );

  Future<void> largeBook() async {
    for (var i = 1; i <= 32; i++) {
      await db
          .into(db.paragraphs)
          .insert(
            ParagraphsCompanion.insert(
              chapterId: chapter,
              paragraphIndex: i,
              type: ParagraphType.paragraph,
              content: 'Ordered paragraph $i about the garden.',
              groupIndex: const Value(null),
            ),
          );
    }
  }

  Future<ChatTurn> latest() async =>
      (await chat.watchTurns(book.bookId, turn.sessionId).first).last;

  test('global scans actual ordered content, persists partial, continues without repeating or changing prior answer', () async {
    await largeBook();
    adapter.strategy = 'global';
    final progress = <int>[];
    final prepared = (await context.prepare(
      turn,
      onExplorationProgress: (n, _) => progress.add(n),
    ))!;
    expect(adapter.embeddingModels, isEmpty);
    expect(adapter.batches, hasLength(3));
    expect(progress, [0, 8, 16, 24]);
    final frame = (await prepared.stream().toList()).last;
    expect(frame.answer!.status, ChatAnswerStatus.partial);
    expect(frame.answer!.blocks.last.text, contains('24/34'));
    await chat.finalize(
      turn.attemptRef,
      phase: ChatPhase.done,
      draft: frame.draft,
      answer: frame.answer,
    );
    final frozen = await (db.select(
      db.chatTurns,
    )..where((t) => t.id.equals(turn.id))).getSingle();
    final previous = await latest();
    expect(chatCanContinue(previous), isTrue);
    context.dispose();
    context = reopenContext();
    final count = adapter.requests.length;
    expect((await latest()).exploration, previous.exploration);
    expect(adapter.requests.length, count); // hydration never sends
    final continuation = await chat.continueExploration(previous, model: model);
    final next = (await context.prepare(continuation))!;
    final finalFrame = (await next.stream().toList()).last;
    await chat.finalize(
      continuation.attemptRef,
      phase: ChatPhase.done,
      draft: finalFrame.draft,
      answer: finalFrame.answer,
    );
    final all = adapter.batches.expand((b) => b).toList();
    expect(all, [for (var i = 1; i <= 34; i++) 'S$i']);
    expect(all.toSet(), hasLength(34));
    expect(
      ChatExploration.parse((await latest()).exploration!).complete,
      isTrue,
    );
    expect(chatCanContinue(await latest()), isFalse);
    expect(
      await (db.select(
        db.chatTurns,
      )..where((t) => t.id.equals(turn.id))).getSingle(),
      frozen,
    );
    expect(await db.select(db.readingProgress).get(), isEmpty);
    expect(await db.select(db.readingSessions).get(), isEmpty);
    expect(
      (await db.select(db.books).get()).every(
        (b) => b.readingSeconds == 0 && b.finishedAt == null,
      ),
      isTrue,
    );
  });

  test('bad batch is not retried; durable earlier batch survives explicit continuation', () async {
    await largeBook();
    adapter.strategy = 'global';
    adapter.badBatch = 2;
    await expectLater(context.prepare(turn), fails(AiError.invalidResponse));
    expect(adapter.batches.length, 2);
    await chat.finalize(
      turn.attemptRef,
      phase: ChatPhase.failed,
      error: AiError.invalidResponse,
    );
    final saved = await latest();
    expect(ChatExploration.parse(saved.exploration!).cursor, 8);
    adapter.badBatch = null;
    final continued = await chat.continueExploration(saved, model: model);
    await context.prepare(continued);
    expect(adapter.batches[2].first, 'S9');
  });

  test(
    'cancelled global response cannot commit coverage or freeze sources',
    () async {
      await largeBook();
      adapter.strategy = 'global';
      final cancel = CancelToken();
      adapter.onBatch = () async {
        cancel.cancel();
        await chat.finalize(turn.attemptRef, phase: ChatPhase.stopped);
      };
      await expectLater(
        context.prepare(turn, cancel: cancel),
        throwsA(anything),
      );
      expect(ChatExploration.parse((await latest()).exploration!).cursor, 0);
      expect((await latest()).answer, isNull);
      expect(adapter.batches, hasLength(1));
    },
  );

  test('checkpoint rejects changed content, foreign identity and changed model before paid work', () async {
    await largeBook();
    adapter.strategy = 'global';
    await context.prepare(turn);
    await chat.finalize(turn.attemptRef, phase: ChatPhase.stopped);
    final saved = await latest();
    await expectLater(
      chat.continueExploration(saved, model: 'different/model'),
      throwsFormatException,
    );
    final continued = await chat.continueExploration(saved, model: model);
    await (db.update(db.paragraphs)..where(
          (p) => p.chapterId.equals(chapter) & p.paragraphIndex.equals(1),
        ))
        .write(const ParagraphsCompanion(content: Value('changed')));
    final count = adapter.requests.length;
    await expectLater(
      context.prepare(continued),
      fails(AiError.invalidResponse),
    );
    expect(adapter.requests.length, count);
  });

  test('off-topic and clarification skip indexing; cross-chapter queries share one query embedding request', () async {
    adapter.strategy = 'offTopic';
    await context.prepare(turn);
    expect(adapter.embeddingModels, isEmpty);
    adapter.strategy = 'crossChapter';
    adapter.queries = ['early garden', 'late roses'];
    await context.prepare(await first());
    final query =
        adapter.requests.where((r) => r.path == '/embeddings').last.data as Map;
    expect(query['input'], hasLength(3));
    expect((query['input'] as List)[1], contains('early garden'));
    expect((query['input'] as List)[2], contains('late roses'));
    expect(documentRequests(), 1);
  });

  test('missing evidence triggers bounded fresh searches and reuses document index', () async {
    adapter.missingQueries = ['other evidence'];
    await context.prepare(turn);
    expect(
      adapter.requests.where((r) => r.path == '/embeddings'),
      hasLength(3),
    ); // docs plus two query batches
    expect(documentRequests(), 1);
    expect(
      adapter.requests.where((r) => r.path != '/embeddings'),
      hasLength(3),
    ); // plan and two selectors
  });

  test('search cap yields a durable continuation and does not repeat completed subqueries', () async {
    var selections = 0;
    adapter.onSelect = () async {
      selections++;
      adapter.missingQueries = ['Missing part $selections'];
    };
    final prepared = (await context.prepare(turn))!;
    final frame = (await prepared.stream().toList()).last;
    expect(frame.answer!.status, ChatAnswerStatus.partial);
    expect(frame.answer!.blocks.last.text, contains('kebutuhan pencarian'));
    await chat.finalize(
      turn.attemptRef,
      phase: ChatPhase.done,
      draft: frame.draft,
      answer: frame.answer,
    );
    final previous = await latest();
    final work = ChatExploration.parse(previous.exploration!);
    expect(work.searchedQueries, hasLength(3));
    expect(work.pendingQueries, ['Missing part 3']);
    final attempts = await Future.wait([
      for (var i = 0; i < 2; i++)
        chat
            .continueExploration(previous, model: model)
            .then<ChatTurn?>((t) => t)
            .catchError((Object _) => null),
    ]);
    expect(attempts.whereType<ChatTurn>(), hasLength(1));
    final continuation = attempts.whereType<ChatTurn>().single;
    adapter.onSelect = () async {
      adapter.missingQueries = [];
    };
    final resumed = (await context.prepare(continuation))!;
    expect(resumed.prompt.sources, isNotEmpty);
    final saved = ChatExploration.parse((await latest()).exploration!);
    expect(saved.searchedQueries, [...work.searchedQueries, 'Missing part 3']);
    expect(saved.complete, isTrue);
    expect(documentRequests(), 1);
  });

  test('long valid conversation history resolves in planner without overflowing query embeddings', () async {
    expect(await chat.prepareSources(turn.attemptRef, []), isTrue);
    await chat.finalize(
      turn.attemptRef,
      phase: ChatPhase.done,
      answer: ChatAnswer(
        formatVersion: 2,
        status: ChatAnswerStatus.answered,
        blocks: [
          ChatAnswerBlock(
            text: 'Context ' * 1400,
            kind: ChatAnswerKind.conversation,
            sources: [],
          ),
        ],
      ),
    );
    final next = await chat.appendTurn(
      book,
      turn.sessionId,
      question: 'Lalu siapa yang menjaga taman itu?',
      model: model,
      promptVersion: chatPromptVersion,
    );
    final prepared = (await context.prepare(next))!;
    expect(prepared.prompt.historyTurnIds, [turn.id]);
    final queryRequest =
        adapter.requests.where((r) => r.path == '/embeddings').last.data as Map;
    expect(
      (queryRequest['input'] as List).every(
        (q) => utf8.encode(q as String).length <= 8000,
      ),
      isTrue,
    );
    final planRequest = adapter.requests.first.data as Map;
    expect(jsonEncode(planRequest), contains('Context Context'));
  });

  test('concurrent preparation shares document indexing work', () async {
    final second = await first();
    await Future.wait([context.prepare(turn), context.prepare(second)]);
    expect(documentRequests(), 1);
  });

  test(
    'fallback reuses durable Large documents without discarding Qwen',
    () async {
      adapter.embeddingStatus = 503;
      adapter.failQueryOnly = true;
      await context.prepare(turn);
      expect(adapter.embeddingModels, hasLength(4));
      context.dispose();
      context = reopenContext();
      await context.prepare(await first());
      expect(adapter.embeddingModels, hasLength(6));
      expect(await db.select(db.chatIndexes).get(), hasLength(2));
    },
  );

  test('document index survives repository restart and A to B to A', () async {
    await context.prepare(turn);
    expect(documentRequests(), 1);
    context.dispose();
    context = reopenContext();
    final next = await first();
    await context.prepare(next);
    expect(documentRequests(), 1);
    final foreign = await chat.createFirstTurn(
      other,
      question: 'Who?',
      model: model,
      promptVersion: chatPromptVersion,
    );
    adapter.emptySelection = true;
    await context.prepare(foreign);
    adapter.emptySelection = false;
    expect(documentRequests(), 2);
    await context.prepare(await first());
    expect(documentRequests(), 2);
    expect(await db.select(db.chatIndexes).get(), hasLength(2));
  });

  test('cancel after durable batch resumes without document request', () async {
    final cancel = CancelToken();
    final progress = <int>[];
    await expectLater(
      context.prepare(
        turn,
        cancel: cancel,
        onIndexProgress: (done, total) {
          progress.add(done);
          if (done == total) cancel.cancel();
        },
      ),
      throwsA(isA<DioException>()),
    );
    expect(progress, [0, 2]);
    expect(documentRequests(), 1);
    context.dispose();
    context = reopenContext();
    expect(await context.prepare(turn), isNotNull);
    expect(documentRequests(), 1);
  });

  test('metadata and answer model changes reuse document vectors', () async {
    await context.prepare(turn);
    await (db.update(db.books)..where((b) => b.id.equals(book.bookId))).write(
      const BooksCompanion(title: Value('New title')),
    );
    context.dispose();
    context = reopenContext();
    await (db.update(db.settings)..where((s) => s.key.equals('ai.model')))
        .write(const SettingsCompanion(value: Value('different/answer')));
    final next = await chat.createFirstTurn(
      book,
      question: 'Who?',
      model: 'different/answer',
      promptVersion: chatPromptVersion,
    );
    await context.prepare(next);
    expect(documentRequests(), 1);
  });

  test(
    'interrupted multi-batch indexing resumes only missing documents',
    () async {
      for (var i = 11; i < 78; i++) {
        await addChapter(book.bookId, i, 'The keeper tends garden number $i.');
      }
      final token = CancelToken();
      await expectLater(
        context.prepare(
          turn,
          cancel: token,
          onIndexProgress: (done, total) {
            if (done == 64) token.cancel();
          },
        ),
        throwsA(isA<DioException>()),
      );
      expect(await db.select(db.chatVectors).get(), hasLength(64));
      expect((await db.select(db.chatIndexes).getSingle()).ready, isFalse);
      context.dispose();
      context = reopenContext();
      final before = adapter.requests.length;
      await context.prepare(turn);
      final docs = adapter.requests
          .skip(before)
          .where(
            (r) =>
                r.path == '/embeddings' &&
                !(((r.data as Map)['input'] as List).first as String)
                    .startsWith(chatQueryPrefix),
          );
      expect(docs, hasLength(1));
      expect(((docs.single.data as Map)['input'] as List).length, 5);
      expect((await db.select(db.chatIndexes).getSingle()).ready, isTrue);
    },
  );

  for (final change in ['stop', 'revision', 'dispose']) {
    test('late embedding cannot commit after $change', () async {
      adapter.onEmbedding = () async {
        adapter.onEmbedding = null;
        if (change == 'stop') {
          await chat.finalize(
            turn.attemptRef,
            phase: ChatPhase.stopped,
            draft: '',
          );
        } else if (change == 'revision') {
          await db.contentChanged(book.bookId);
        } else {
          context.dispose();
        }
      };
      await expectLater(context.prepare(turn), throwsStateError);
      expect(await db.select(db.chatVectors).get(), isEmpty);
    });
  }

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
        promptVersion: chatPromptVersion,
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

  test('revision alone invalidates cached vectors and prepared answer even with identical text', () async {
    final old = (await context.prepare(turn))!;
    await chat.finalize(turn.attemptRef, phase: ChatPhase.stopped);
    await db.contentChanged(book.bookId);
    final next = await chat.createFirstTurn(
      (bookId: book.bookId, contentRevision: 2),
      question: 'Siapa?',
      model: model,
      promptVersion: chatPromptVersion,
    );
    final prepared = (await context.prepare(next))!;
    expect(
      prepared.prompt.sources.every(
        (s) => s.anchors.every((a) => a.book.contentRevision == 2),
      ),
      true,
    );
    expect(
      adapter.requests.where((r) => r.path == '/embeddings'),
      hasLength(4),
    );
    final requests = adapter.requests.length;
    expect(await old.stream().toList(), isEmpty);
    expect(adapter.requests.length, requests);
  });

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

  test('clarification and empty selection get conversational answers without invented sources', () async {
    adapter.clarification = true;
    var prepared = (await context.prepare(turn))!;
    expect(
      (await prepared.stream().last).answer!.status,
      ChatAnswerStatus.clarify,
    );
    expect(adapter.requests, hasLength(2));
    expect(adapter.embeddingModels, isEmpty);
    await chat.finalize(turn.attemptRef, phase: ChatPhase.stopped);
    turn = await first();
    adapter.clarification = false;
    adapter.badRewrite = true;
    await expectLater(context.prepare(turn), fails(AiError.invalidResponse));
    expect(adapter.requests, hasLength(3));
    adapter.badRewrite = false;
    adapter.emptySelection = true;
    prepared = (await context.prepare(turn))!;
    expect(
      (await prepared.stream().last).answer!.status,
      ChatAnswerStatus.partial,
    );
    expect(
      adapter.requests.where(
        (r) =>
            ((r.data as Map)['messages'] as List?)?.first['content'] ==
            chatAnswerSystemPrompt,
      ),
      hasLength(2),
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
        promptVersion: chatPromptVersion,
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
      promptVersion: chatPromptVersion,
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
