import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/chat_context_repository.dart';
import 'package:luma/data/repositories/chat_notes_repository.dart';
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

  /// Context window kecil supaya pembacaan terbagi beberapa batch.
  int contextLength = 32000;
  bool modelsFail = false;
  bool longNotesOnce = false;
  int selections = 0;
  final overviewSystems = <bool>[];
  bool alwaysBadBatch = false;
  List<int> chapterIds = const [];
  List<Object> skipIds = const [];
  List<List<int>>? selectionsByRound;
  String? clarificationText;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/models') {
      if (modelsFail) return json({'error': 'down'}, 503);
      return json({
        'data': [
          {'id': 'chosen/model', 'context_length': contextLength},
        ],
      });
    }
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
    if (system == chatPlanSystem) {
      raw = badRewrite
          ? 'invalid'
          : jsonEncode({
              'query': 'Who keeps the garden?',
              'needs_clarification': clarification,
              if (clarificationText != null) 'clarification': clarificationText,
              'strategy': strategy,
              'chapter_ids': chapterIds,
              'skip_ids': skipIds,
              'queries': queries,
            });
    } else if (system == chatGlobalSystem || system == chatOverviewSystem) {
      overviewSystems.add(system == chatOverviewSystem);
      final user =
          jsonDecode((messages.last as Map)['content'] as String) as Map;
      final batch = (user['newWindowIds'] as List).cast<String>();
      if (user['repair'] == null) batches.add(batch);
      await onBatch?.call();
      if (longNotesOnce && user['repair'] == null) {
        longNotesOnce = false;
        raw = jsonEncode({
          'notes': [
            {
              'text': 'x' * (chatBatchNotesChars + 1),
              'source_ids': [batch.first],
            },
          ],
        });
        return sse([
          for (final rune in raw.runes) event(String.fromCharCode(rune)),
          'data: [DONE]\n\n',
        ]);
      }
      raw = jsonEncode({
        'notes': [
          {
            'text': 'Gagasan diperiksa.',
            'source_ids': [
              alwaysBadBatch || badBatch == batches.length
                  ? 'S99999'
                  : batch.first,
            ],
          },
        ],
      });
    } else if (system == chatSelectionSystem) {
      await onSelect?.call();
      final offered =
          ((jsonDecode((messages.last as Map)['content'] as String)
                      as Map)['candidates']
                  as List)
              .length;
      selections++;
      raw = jsonEncode({
        'resolved_question': 'Who keeps it?',
        'selected': selectionsByRound != null
            ? selectionsByRound![selections - 1]
            : emptySelection
            ? []
            : [for (var i = 1; i <= (offered < 2 ? offered : 2); i++) i],
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

  /// Context kecil memecah 34 window jadi beberapa batch; budget token kecil
  /// memaksa berhenti sebelum selesai (partial + Lanjutkan).
  ChatContextRepository limitedContext() => ChatContextRepository(
    db,
    chat,
    OpenRouterService(
      Dio(BaseOptions(baseUrl: 'https://openrouter.ai/api/v1'))
        ..httpClientAdapter = adapter,
    ),
    keys,
    tokenBudget: 60000,
  );

  Future<void> largeBook() async {
    adapter.contextLength = 14000;
    for (var i = 1; i <= 32; i++) {
      await db
          .into(db.paragraphs)
          .insert(
            ParagraphsCompanion.insert(
              chapterId: chapter,
              paragraphIndex: i,
              type: ParagraphType.paragraph,
              content:
                  'Ordered paragraph $i about the garden. ${'The keeper tends the beds daily. ' * 28}',
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
    context.dispose();
    context = limitedContext();
    final prepared = (await context.prepare(
      turn,
      onExplorationProgress: (p) => progress.add(p.completed),
    ))!;
    expect(adapter.embeddingModels, isEmpty);
    expect(adapter.batches.length, greaterThanOrEqualTo(2));
    final examined = adapter.batches.fold<int>(0, (n, b) => n + b.length);
    expect(examined, lessThan(34));
    expect(progress.first, 0);
    expect(progress.last, examined);
    final frame = (await prepared.stream().toList()).last;
    expect(frame.answer!.status, ChatAnswerStatus.partial);
    expect(frame.answer!.blocks.last.text, contains('$examined/34'));
    expect(
      ChatExploration.parse((await latest()).exploration!).stopReason,
      'budget',
    );
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

  test('invalid batch notes are repaired once; exhausted repairs fail without losing durable batches', () async {
    await largeBook();
    adapter.strategy = 'global';
    adapter.badBatch = 2;
    await context.prepare(turn);
    final repairs = adapter.requests.where(
      (r) =>
          r.path == '/chat/completions' &&
          ((r.data as Map)['messages'] as List).length == 4,
    );
    expect(repairs, hasLength(1));
    expect(
      ((repairs.single.data as Map)['messages'] as List)[1]['content'],
      contains('S99999'),
    );
    expect(
      ChatExploration.parse((await latest()).exploration!).complete,
      isTrue,
    );
    await chat.finalize(turn.attemptRef, phase: ChatPhase.stopped);

    adapter.badBatch = null;
    adapter.alwaysBadBatch = true;
    await db.delete(db.chatChapterNotes).go(); // force a fresh read
    final again = await first();
    await expectLater(context.prepare(again), fails(AiError.invalidResponse));
    final saved = ChatExploration.parse(
      (await chat.watchTurns(book.bookId, again.sessionId).first)
          .last
          .exploration!,
    );
    expect(saved.cursor, 0);
    expect(saved.chapterIds, isNotEmpty);
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
    context.dispose();
    context = limitedContext();
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

  Map<String, Object?> lastUserJson(String system) => jsonDecode(
    ((adapter.requests
                        .where(
                          (r) =>
                              r.path == '/chat/completions' &&
                              ((r.data as Map)['messages'] as List)
                                      .first['content'] ==
                                  system,
                        )
                        .last
                        .data
                    as Map)['messages']
                as List)
            .last['content']
        as String,
  ) as Map<String, Object?>;

  test(
    'planner sees the original toc, sections and reading position',
    () async {
      await (db.update(db.chapters)..where((c) => c.id.equals(chapter))).write(
        const ChaptersCompanion(
          title: Value('III: Of the garden'),
          section: Value('Discourses › Book I'),
        ),
      );
      adapter.strategy = 'chapters';
      adapter.chapterIds = [chapter];
      await context.prepare(turn, readingChapterId: chapter);
      final plan = lastUserJson(chatPlanSystem);
      final toc = plan['toc'] as List;
      expect(toc, hasLength(2));
      expect(toc.first, {
        'id': chapter,
        'section': 'Discourses › Book I',
        'title': 'III: Of the garden',
        'number': 3,
        'chars': text.length,
      });
      expect((toc.last as Map).containsKey('section'), isFalse);
      expect(plan['readingPosition'], {
        'chapterId': chapter,
        'label': 'Book I › III: Of the garden',
      });
      expect(plan['book'], {'title': 'Garden', 'author': ''});
      expect(plan['history'], isEmpty);
    },
  );

  test('chapters strategy reads the requested chapter directly, without embeddings or notes', () async {
    adapter.strategy = 'chapters';
    adapter.chapterIds = [chapter];
    final prepared = (await context.prepare(turn))!;
    expect(adapter.embeddingModels, isEmpty);
    expect(adapter.batches, isEmpty);
    expect(
      adapter.requests.where((r) => r.path == '/chat/completions'),
      hasLength(1),
    ); // planner only; the answer is not sent yet
    expect(prepared.prompt.sources.single.text, text);
    expect(prepared.prompt.sources.single.chapterTitle, 'Chapter 0');
    final user = jsonDecode(prepared.prompt.user) as Map;
    expect(user['exploration'], {
      'scope': 'chapters',
      'complete': true,
      'examinedChapters': ['Chapter 0'],
      'chapterCount': 1,
      'examinedWindows': 1,
      'totalWindows': 1,
      'notesAreGenerated': true,
      'notes': [],
    });
    final work = ChatExploration.parse((await latest()).exploration!);
    expect(work.strategy, ChatSearchStrategy.chapters);
    expect(work.chapterIds, [chapter]);
    expect(work.complete, isTrue);
    final frame = (await prepared.stream().toList()).last;
    expect(frame.answer!.status, ChatAnswerStatus.answered);
    expect(frame.answer!.blocks.single.sources.single.text, text);
  });

  test(
    'a long requested chapter is read in batches within the shared budget',
    () async {
      await largeBook();
      adapter.strategy = 'chapters';
      adapter.chapterIds = [chapter];
      context.dispose();
      context = limitedContext();
      final prepared = (await context.prepare(turn))!;
      expect(adapter.embeddingModels, isEmpty);
      expect(adapter.batches.length, greaterThanOrEqualTo(2));
      expect(
        adapter.batches.expand((b) => b).every((id) => id.startsWith('S')),
        isTrue,
      );
      final examined = adapter.batches.fold<int>(0, (n, b) => n + b.length);
      final frame = (await prepared.stream().toList()).last;
      expect(frame.answer!.status, ChatAnswerStatus.partial);
      expect(frame.answer!.blocks.last.text, contains('dari bab yang diminta'));
      expect(frame.answer!.blocks.last.text, contains('$examined/33'));
      final user = jsonDecode(prepared.prompt.user) as Map;
      expect((user['exploration'] as Map)['scope'], 'chapters');
      expect((user['exploration'] as Map)['stopReason'], 'budget');
      // Notes cite windows that were packed into the final sources only.
      final ids = prepared.prompt.sources.map((s) => s.id).toSet();
      for (final note in (user['exploration'] as Map)['notes'] as List) {
        expect(ids.containsAll((note as Map)['source_ids'] as List), isTrue);
      }
    },
  );

  test('progress names the chapter being read, carries saved notes, and Jawab sekarang stops after the running group', () async {
    for (var i = 1; i <= 120; i++) {
      await db
          .into(db.paragraphs)
          .insert(
            ParagraphsCompanion.insert(
              chapterId: chapter,
              paragraphIndex: i,
              type: ParagraphType.paragraph,
              content:
                  'Ordered paragraph $i. ${'The keeper tends the beds. ' * 36}',
              groupIndex: const Value(null),
            ),
          );
    }
    adapter.contextLength = 20000; // ~19 windows per batch, several groups
    final other =
        await (db.select(db.chapters)..where(
              (c) => c.bookId.equals(book.bookId) & c.id.equals(chapter).not(),
            ))
            .getSingle();
    await (db.update(db.chapters)..where((c) => c.id.equals(chapter))).write(
      const ChaptersCompanion(
        title: Value('IV: Of Progress'),
        section: Value('Discourses › Book I'),
      ),
    );
    adapter.strategy = 'global';
    adapter.chapterIds = [chapter, other.id];
    final seen = <ChatExplorationProgress>[];
    var groups = 0;
    adapter.onBatch = () async {
      groups++;
    };
    final prepared = (await context.prepare(
      turn,
      onExplorationProgress: seen.add,
      answerNow: () => groups >= 1,
    ))!;
    expect(seen.first.completed, 0);
    expect(seen.first.notes, isEmpty);
    expect(
      seen.map((p) => p.label).whereType<String>().first,
      'Book I › IV: Of Progress',
    );
    final saved = seen.where((p) => p.notes.isNotEmpty).toList();
    expect(saved, isNotEmpty);
    expect(
      saved.last.notes.length,
      saved.last.completed == 0 ? 0 : greaterThan(0),
    );
    final work = ChatExploration.parse((await latest()).exploration!);
    expect(work.complete, isFalse);
    expect(work.stopReason, 'user');
    expect(work.cursor, seen.last.completed);
    final frame = (await prepared.stream().toList()).last;
    expect(frame.answer!.status, ChatAnswerStatus.partial);
    await chat.finalize(
      turn.attemptRef,
      phase: ChatPhase.done,
      draft: frame.draft,
      answer: frame.answer,
    );
    expect(chatCanContinue(await latest()), isTrue);
    // Batches split at the chapter boundary once they are mostly full.
    for (final batch in adapter.batches) {
      expect(batch, isNotEmpty);
    }
  });

  test(
    'document embeddings are requested in parallel and stored in order',
    () async {
      for (var i = 1; i <= 200; i++) {
        await db
            .into(db.paragraphs)
            .insert(
              ParagraphsCompanion.insert(
                chapterId: chapter,
                paragraphIndex: i,
                type: ParagraphType.paragraph,
                content: 'Garden paragraph $i.',
                groupIndex: Value(i),
              ),
            );
      }
      var inFlight = 0, peak = 0;
      adapter.onEmbedding = () async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
      };
      await context.prepare(turn);
      expect(peak, greaterThan(1));
      expect(documentRequests(), 4); // 202 chunks / 64
      final vectors = await (db.select(
        db.chatVectors,
      )..orderBy([(v) => OrderingTerm.asc(v.ordinal)])).get();
      expect(vectors.map((v) => v.ordinal), List.generate(202, (i) => i));
    },
  );

  test(
    'whole-book notes are cached per chapter and reused on the next send',
    () async {
      await largeBook();
      adapter.contextLength = 40000;
      final other =
          await (db.select(db.chapters)..where(
                (c) =>
                    c.bookId.equals(book.bookId) & c.id.equals(chapter).not(),
              ))
              .getSingle();
      adapter.strategy = 'global';
      adapter.chapterIds = [chapter, other.id];
      final first = (await context.prepare(turn))!;
      expect(adapter.batches, isNotEmpty);
      expect(
        adapter.overviewSystems,
        everyElement(isTrue),
      ); // question-agnostic
      final notesRepo = ChatNotesRepository(db);
      expect(await notesRepo.count(book.bookId), 2);
      final frame = (await first.stream().toList()).last;
      await chat.finalize(
        turn.attemptRef,
        phase: ChatPhase.done,
        draft: frame.draft,
        answer: frame.answer,
      );
      final before = adapter.batches.length;
      final again = await chat.appendTurn(
        book,
        turn.sessionId,
        question: 'Tema kematian di buku ini?',
        model: model,
        promptVersion: chatPromptVersion,
      );
      final second = (await context.prepare(again))!;
      expect(adapter.batches.length, before); // no notes request at all
      final work = ChatExploration.parse((await latest()).exploration!);
      expect(work.complete, isTrue);
      expect(work.notes, isNotEmpty);
      final user = jsonDecode(second.prompt.user) as Map;
      expect((user['exploration'] as Map)['notesFromCache'], 2);
      expect((user['exploration'] as Map)['notes'], isNotEmpty);
      expect(second.prompt.sources, isNotEmpty);
      final frame2 = (await second.stream().toList()).last;
      expect(frame2.answer, isNotNull);
      await chat.finalize(
        again.attemptRef,
        phase: ChatPhase.done,
        draft: frame2.draft,
        answer: frame2.answer,
      );

      // Changed content invalidates the cache; the chapter is read again.
      await db.contentChanged(book.bookId);
      expect(await notesRepo.count(book.bookId), 0);
    },
  );

  test('a changed chapter manifest rereads only that chapter', () async {
    await largeBook();
    adapter.contextLength = 40000;
    final other =
        await (db.select(db.chapters)..where(
              (c) => c.bookId.equals(book.bookId) & c.id.equals(chapter).not(),
            ))
            .getSingle();
    adapter.strategy = 'global';
    adapter.chapterIds = [chapter, other.id];
    await context.prepare(turn);
    await chat.finalize(turn.attemptRef, phase: ChatPhase.stopped);
    // Simulate a stale cached row for the small chapter.
    await (db.update(db.chatChapterNotes)
          ..where((n) => n.chapterId.equals(other.id)))
        .write(const ChatChapterNotesCompanion(manifest: Value('stale')));
    adapter.batches.clear();
    await context.prepare(await first());
    expect(adapter.batches, hasLength(1));
    expect(adapter.batches.single.every((id) => id.startsWith('S')), isTrue);
    final work = ChatExploration.parse(
      (await chat
              .watchTurns(
                book.bookId,
                (await db.select(db.chatSessions).get()).last.id,
              )
              .first)
          .last
          .exploration!,
    );
    expect(work.chapterIds.first, chapter); // cached chapter read first
    expect(work.complete, isTrue);
  });

  test(
    'stopping mid-read keeps the notes of chapters already finished',
    () async {
      await largeBook();
      final other =
          await (db.select(db.chapters)..where(
                (c) =>
                    c.bookId.equals(book.bookId) & c.id.equals(chapter).not(),
              ))
              .getSingle();
      adapter.strategy = 'global';
      adapter.chapterIds = [other.id, chapter];
      var groups = 0;
      adapter.onBatch = () async {
        groups++;
      };
      context.dispose();
      context = limitedContext();
      await context.prepare(turn, answerNow: () => groups >= 1);
      final notesRepo = ChatNotesRepository(db);
      final cached = await (db.select(db.chatChapterNotes)).get();
      expect(
        cached.map((n) => n.chapterId),
        contains(other.id),
      ); // small, finished first
      expect(await notesRepo.count(book.bookId), lessThan(2));
    },
  );

  test(
    'search candidates skip chapters outside the planner\'s content list',
    () async {
      adapter.strategy = 'specific';
      adapter.chapterIds = [chapter];
      final prepared = (await context.prepare(turn))!;
      expect(
        prepared.prompt.sources.every(
          (s) => s.anchors.first.chapterId == chapter,
        ),
        isTrue,
      );
      final work = ChatExploration.parse((await latest()).exploration!);
      expect(work.chapterIds, [chapter]);
    },
  );

  test('skip_ids keep front/back matter out of whole-book reads and search; string ids are accepted', () async {
    await largeBook();
    adapter.contextLength = 40000;
    final other =
        await (db.select(db.chapters)..where(
              (c) => c.bookId.equals(book.bookId) & c.id.equals(chapter).not(),
            ))
            .getSingle();
    adapter.strategy = 'global';
    adapter.skipIds = ['${other.id}'];
    await context.prepare(turn);
    final work = ChatExploration.parse((await latest()).exploration!);
    expect(work.chapterIds, [chapter]);
    await chat.finalize(turn.attemptRef, phase: ChatPhase.stopped);

    adapter.strategy = 'specific';
    adapter.skipIds = [chapter];
    final searched = await first();
    final prepared = (await context.prepare(searched))!;
    expect(
      prepared.prompt.sources.every(
        (s) => s.anchors.first.chapterId == other.id,
      ),
      isTrue,
    );
    expect(
      ChatExploration.parse(
        (await chat.watchTurns(book.bookId, searched.sessionId).first)
            .last
            .exploration!,
      ).chapterIds,
      [other.id],
    );
  });

  test(
    'later search rounds add evidence without dropping earlier picks',
    () async {
      adapter.selectionsByRound = [
        [1],
        [],
      ];
      adapter.missingQueries = ['another angle'];
      final prepared = (await context.prepare(turn))!;
      expect(prepared.prompt.sources, isNotEmpty);
      expect(adapter.selections, 2);
    },
  );

  test('global reads only the planner\'s content chapters', () async {
    await largeBook();
    adapter.strategy = 'global';
    adapter.chapterIds = [chapter];
    await context.prepare(turn);
    final work = ChatExploration.parse((await latest()).exploration!);
    expect(work.chapterIds, [chapter]);
    expect(work.total, 33);
    expect(work.complete, isTrue);
    for (final batch in adapter.batches) {
      final user = lastUserJson(chatOverviewSystem);
      expect(user['examinedBefore'], isA<int>());
      expect(batch, isNotEmpty);
    }
    expect(
      adapter.requests
          .where((r) => r.path == '/chat/completions')
          .map((r) => (r.data as Map)['stream_options']),
      everyElement({'include_usage': true}),
    );
  });

  test('clarification from the planner reaches the answer prompt without any retrieval', () async {
    adapter.strategy = 'chapters';
    adapter.clarification = true;
    adapter.clarificationText = 'Book I bab III atau Book III?';
    final prepared = (await context.prepare(turn))!;
    expect(adapter.embeddingModels, isEmpty);
    expect(adapter.batches, isEmpty);
    expect(prepared.prompt.sources, isEmpty);
    final user = jsonDecode(prepared.prompt.user) as Map;
    expect(user['exploration'], {
      'clarification': 'Book I bab III atau Book III?',
    });
    expect((await latest()).exploration, isNull);
    final frame = (await prepared.stream().toList()).last;
    expect(frame.answer!.status, ChatAnswerStatus.clarify);
  });

  test(
    'a bare chapter number shared across books asks instead of guessing',
    () async {
      final other =
          await (db.select(db.chapters)..where(
                (c) =>
                    c.bookId.equals(book.bookId) & c.id.equals(chapter).not(),
              ))
              .getSingle();
      await (db.update(db.chapters)..where((c) => c.id.equals(chapter))).write(
        const ChaptersCompanion(
          title: Value('III: Of the garden'),
          section: Value('Discourses › Book I'),
        ),
      );
      await (db.update(db.chapters)..where((c) => c.id.equals(other.id))).write(
        const ChaptersCompanion(
          title: Value('III: Of roses'),
          section: Value('Discourses › Book II'),
        ),
      );
      final asked = await chat.createFirstTurn(
        book,
        question: 'bab III bahas apa?',
        model: model,
        promptVersion: chatPromptVersion,
      );
      adapter.strategy = 'chapters';
      adapter.chapterIds = [chapter];
      final prepared = (await context.prepare(asked))!;
      expect(prepared.prompt.sources, isEmpty);
      final user = jsonDecode(prepared.prompt.user) as Map;
      expect(
        (user['exploration'] as Map)['clarification'],
        'Maksud lo bab yang di Book I, Book II yang mana?',
      );
      expect((await latest()).exploration, isNull);
      // The reading position inside Book I settles it without asking.
      expect(
        await chat.finalize(asked.attemptRef, phase: ChatPhase.stopped),
        isTrue,
      );
      final settled = await chat.appendTurn(
        book,
        asked.sessionId,
        question: 'bab III bahas apa?',
        model: model,
        promptVersion: chatPromptVersion,
      );
      final direct = (await context.prepare(
        settled,
        readingChapterId: chapter,
      ))!;
      expect(direct.prompt.sources.single.text, text);
    },
  );

  test('oversized notes are repaired once within the shared ledger', () async {
    await largeBook();
    adapter.strategy = 'global';
    adapter.chapterIds = [chapter];
    adapter.longNotesOnce = true;
    adapter.contextLength = 40000; // retry resends the long output as history
    await context.prepare(turn);
    final notes = adapter.requests.where(
      (r) =>
          r.path == '/chat/completions' &&
          [
            chatGlobalSystem,
            chatOverviewSystem,
          ].contains(((r.data as Map)['messages'] as List).first['content']),
    );
    expect(notes.length, adapter.batches.length + 1);
    final repairRequest = notes.singleWhere(
      (r) => ((r.data as Map)['messages'] as List).length == 4,
    );
    final repair = jsonDecode(
      ((repairRequest.data as Map)['messages'] as List).last['content']
          as String,
    ) as Map;
    expect(repair['repair'], contains('Catatan melebihi budget'));
    expect(
      ChatExploration.parse((await latest()).exploration!).complete,
      isTrue,
    );
  });

  test('chapter ids outside the toc fail before any retrieval', () async {
    adapter.strategy = 'chapters';
    adapter.chapterIds = [999999];
    await expectLater(context.prepare(turn), fails(AiError.invalidResponse));
    expect(adapter.embeddingModels, isEmpty);
    expect(
      adapter.requests.where((r) => r.path == '/chat/completions'),
      hasLength(1),
    );
    expect((await latest()).exploration, isNull);
  });

  test('model metadata failure falls back to a conservative context and still answers', () async {
    adapter.modelsFail = true;
    adapter.strategy = 'chapters';
    adapter.chapterIds = [chapter];
    final prepared = (await context.prepare(turn))!;
    expect(prepared.prompt.sources.single.text, text);
    final frame = (await prepared.stream().toList()).last;
    expect(frame.answer, isNotNull);
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
    // Round two selected the same evidence again: stagnant, stop early.
    expect(work.searchedQueries, hasLength(2));
    expect(work.pendingQueries, ['Missing part 2']);
    expect(work.stopReason, 'stagnant');
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
    expect(saved.searchedQueries, [...work.searchedQueries, 'Missing part 2']);
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
    final previews = frames
        .where(
          (f) => f.answer == null && f.preview.any((b) => b.text.isNotEmpty),
        )
        .toList();
    expect(previews, isNotEmpty);
    expect(previews.first.preview.single.text, 'P');
    expect(previews.first.preview.single.sources, isEmpty);
    expect(previews.last.preview.single.sources, isNotEmpty);
    expect(previews.last.preview.single.text, 'Penjaganya 🌿.');
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
    'invalid citation never becomes a source action; repaired at most twice',
    () async {
      final prepared = (await context.prepare(turn))!;
      adapter.answerId = 'S999';
      final frames = <ChatStreamFrame>[];
      await expectLater(
        prepared.stream().forEach(frames.add),
        fails(AiError.invalidResponse),
      );
      expect(frames.every((f) => f.answer == null), isTrue);
      expect(frames.map((f) => f.repair).toSet(), {0, 1, 2});
      expect(frames.where((f) => f.repairReason != null), isNotEmpty);
      // plan + selector + answer + two repairs, never a fourth answer.
      final answers = adapter.requests.where(
        (r) =>
            r.path == '/chat/completions' &&
            ((r.data as Map)['messages'] as List).first['content'] ==
                chatAnswerSystemPrompt,
      );
      expect(answers, hasLength(3));
      expect(
        ((answers.last.data as Map)['messages'] as List).length,
        4,
      ); // system, user, previous assistant output, repair instruction
      expect(
        adapter.requests.where((r) => r.path == '/chat/completions'),
        hasLength(5),
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
      expect(adapter.requests.where((r) => r.path == '/embeddings'), isEmpty);
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
