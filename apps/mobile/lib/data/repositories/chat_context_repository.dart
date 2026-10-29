import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chat_prompt.dart';
import '../../domain/chat_exploration.dart';
import '../../domain/chat_retrieval.dart';
import '../../domain/models/ai_model.dart';
import '../../domain/models/ai_reply.dart';
import '../../domain/models/book_chat.dart';
import '../database/app_database.dart';
import '../services/api_key_store.dart';
import '../services/openrouter_service.dart';
import 'chat_repository.dart';
import 'chat_index_repository.dart';
import 'chat_snapshot.dart';

/// Each send reads credentials afresh. Document vectors survive in the local DB.
class ChatContextRepository {
  ChatContextRepository(this._db, this._chat, this._router, this._keys);
  final AppDatabase _db;
  final ChatRepository _chat;
  final OpenRouterService _router;
  final ApiKeyStore _keys;
  Future<void> _indexTail = Future.value();
  ChatIndexKey? _indexKey;
  String? _manifest;
  List<Float32List>? _documents;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _documents = null;
    _indexKey = null;
    _manifest = null;
  }

  void _check(CancelToken? cancel) {
    if (_disposed) throw StateError('Konteks chat sudah ditutup');
    if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
  }

  /// For #118 first-send/retry: capture this model when creating the turn.
  Future<String> model() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals('ai.model'))).getSingleOrNull();
    return row?.value ?? defaultAiModel;
  }

  /// Document batches may be cached before evidence is frozen. A stale attempt
  /// never sends an answer. Caller owns checkpoint/finalize and stop lifecycle.
  Future<PreparedChat?> prepare(
    ChatTurn target, {
    CancelToken? cancel,
    void Function(int completed, int total)? onIndexProgress,
    void Function(int completed, int total)? onExplorationProgress,
  }) async {
    _check(cancel);
    final key = await _keys.read();
    _check(cancel);
    if (key == null || key.trim().isEmpty) {
      throw const AiException(AiError.noApiKey);
    }
    await _chat.recoverInterrupted();
    _check(cancel);
    try {
      final budget = _ChatRetrievalBudget();
      final input = await _db.transaction(() async {
        final sessionRow =
            await (_db.select(_db.chatSessions)..where(
                  (s) =>
                      s.id.equals(target.sessionId) &
                      s.bookId.equals(target.book.bookId),
                ))
                .getSingleOrNull();
        final b = await (_db.select(
          _db.books,
        )..where((b) => b.id.equals(target.book.bookId))).getSingleOrNull();
        if (sessionRow == null ||
            b == null ||
            b.contentRevision != target.book.contentRevision) {
          return null;
        }
        final session = ChatSnapshot.session(sessionRow);
        if (session.invalid || session.book != target.book) return null;
        final rows =
            await (_db.select(_db.chatTurns)
                  ..where((t) => t.sessionId.equals(session.id))
                  ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
                .get();
        final turns = rows
            .map((t) => ChatSnapshot.turn(t, sessionRow))
            .toList();
        final matches = turns.where((t) => t.id == target.id).toList();
        if (matches.isEmpty ||
            !matches.single.accepts(target.attemptRef, session.book) ||
            ![
              ChatPhase.preparing,
              ChatPhase.retrieving,
            ].contains(matches.single.phase)) {
          return null;
        }
        final turn = matches.single;
        final selectedModel = await model();
        if (turn.model != selectedModel ||
            turn.promptVersion != chatPromptVersion) {
          throw const FormatException(
            'Model/prompt berubah; mulai ulang attempt secara eksplisit',
          );
        }
        final query =
            _db.select(_db.paragraphs).join([
                innerJoin(
                  _db.chapters,
                  _db.chapters.id.equalsExp(_db.paragraphs.chapterId),
                ),
              ])
              ..where(_db.chapters.bookId.equals(b.id))
              ..orderBy([
                OrderingTerm.asc(_db.chapters.sortOrder),
                OrderingTerm.asc(_db.chapters.id),
                OrderingTerm.asc(_db.paragraphs.paragraphIndex),
              ]);
        final indexed = <ChatIndexedParagraph>[];
        final paragraphs = <ChatParagraphRef, ChatParagraph>{};
        for (final row in await query.get()) {
          final p = row.readTable(_db.paragraphs),
              c = row.readTable(_db.chapters);
          final ChatParagraph paragraph = (
            book: session.book,
            chapterId: c.id,
            paragraphIndex: p.paragraphIndex,
            text: p.content,
          );
          paragraphs[(chapterId: c.id, paragraphIndex: p.paragraphIndex)] =
              paragraph;
          indexed.add((
            paragraph: paragraph,
            chapterTitle: c.title,
            groupIndex: p.groupIndex,
          ));
        }
        if (indexed.fold<int>(
              0,
              (n, r) => n + utf8.encode(r.paragraph.text).length,
            ) >
            chatEmbeddingInputBytes) {
          throw const FormatException('Buku melebihi budget embedding');
        }
        final chunks = chatChunks(indexed, session.book);
        final quoted = chatQuoteSources(chunks, turn.quote);
        // Validate quote coverage, question, history and actual system budget
        // before any paid request. Final selected sources get the same checks.
        final preflight = buildChatPrompt(
          session: session,
          current: session.book,
          question: turn.question,
          beforeSequence: turn.sequence,
          history: turns,
          sources: quoted,
          paragraphs: paragraphs,
          title: b.title,
          author: b.author,
          quote: turn.quote,
        );
        return (
          session: session,
          turn: turn,
          book: b,
          chunks: chunks,
          windows: chatGlobalWindows(indexed),
          paragraphs: paragraphs,
          history: turns,
          quoted: quoted,
          preflight: preflight,
        );
      });
      _check(cancel);
      if (input == null) return null;
      budget.guard = () => _chat.validateRetrieval(target.attemptRef, []);
      final current = input.session.book;
      final history =
          ((jsonDecode(input.preflight.user) as Map)['history'] as List)
              .map((h) => Map<String, String>.from(h as Map))
              .toList();
      final quote = input.turn.quote;
      final rewriteUser = chatRetrievalUser(
        {
          'question': input.turn.question,
          'history': history,
          if (quote != null) 'selectedQuote': quote.text,
        },
        chatRewriteSystem,
        chatPromptBytes,
      );
      // English subqueries resolve history/quote; keep the original query small.
      final original = chatEmbeddingQuery(
        input.turn.question,
        const [],
        null,
        ChatEmbeddingModel.qwen8b,
      );
      final saved = input.turn.exploration == null
          ? null
          : ChatExploration.parse(input.turn.exploration!);
      saved?.validate(
        input.turn,
        saved.strategy == ChatSearchStrategy.global
            ? input.windows
            : input.chunks,
      );
      final plan = saved == null
          ? parseChatQueryPlan(
              await _complete(
                key,
                input.turn.model,
                chatRewriteSystem,
                rewriteUser,
                600,
                cancel,
                budget,
              ),
            )
          : ChatQueryPlan(
              englishQuery: saved.query,
              needsClarification: false,
              strategy: saved.strategy,
              queries: saved.pendingQueries,
            );
      _check(cancel);
      var selected = input.quoted;
      ChatExploration? exploration;
      var noteSourceIds = <String, String>{};
      if (!plan.needsClarification &&
          plan.strategy == ChatSearchStrategy.global &&
          input.windows.isNotEmpty) {
        final globalQuotes = <ChatSource>[];
        for (final (i, source) in input.quoted.indexed) {
          final matches = input.windows.where(
            (w) => _rangeKey(w) == _rangeKey(source),
          );
          globalQuotes.add(
            matches.isNotEmpty
                ? matches.first
                : ChatSource(
                    id: 'S${input.windows.length + i + 1}',
                    chapterTitle: source.chapterTitle,
                    anchors: source.anchors,
                  ),
          );
        }
        var work =
            saved ??
            ChatExploration(
              book: current,
              sessionId: target.sessionId,
              turnId: target.id,
              question: target.question,
              model: target.model,
              manifest: chatWindowManifest(input.windows),
              query: plan.englishQuery,
              cursor: 0,
              total: input.windows.length,
              notes: [],
            );
        if (!await _chat.saveExploration(target.attemptRef, work)) return null;
        onExplorationProgress?.call(work.cursor, work.total);
        for (
          var round = 0;
          round < chatGlobalRounds && !work.complete;
          round++
        ) {
          if (budget.elapsed.elapsed > const Duration(seconds: 100)) break;
          final batch = <ChatSource>[];
          var bytes = 0;
          for (final window in input.windows.skip(work.cursor)) {
            final size = utf8.encode(jsonEncode(_source(window))).length;
            if (batch.isNotEmpty &&
                (bytes + size > chatGlobalBatchBytes || batch.length == 8)) {
              break;
            }
            batch.add(window);
            bytes += size;
          }
          final previousIds = work.notes.expand((n) => n.sourceIds).toSet();
          final evidence = [
            for (final w in input.windows)
              if (previousIds.contains(w.id)) w,
            ...batch,
          ];
          validateChatSources(evidence, current, input.paragraphs);
          final user = chatRetrievalUser(
            {
              'question': target.question,
              'book': input.book.title,
              'examinedBefore': work.cursor,
              'totalWindows': work.total,
              'previousNotes': work.promptData['notes'],
              'sources': [for (final w in evidence) _source(w)],
              'newWindowIds': batch.map((w) => w.id).toList(),
            },
            chatGlobalSystem,
            chatPromptBytes,
          );
          if (!await _chat.validateRetrieval(target.attemptRef, evidence)) {
            return null;
          }
          _check(cancel);
          final notes = parseChatGlobalNotes(
            await _complete(
              key,
              target.model,
              chatGlobalSystem,
              user,
              1400,
              cancel,
              budget,
            ),
            allowed: evidence.map((s) => s.id).toSet(),
          );
          final next = ChatExploration(
            book: current,
            sessionId: target.sessionId,
            turnId: target.id,
            question: target.question,
            model: target.model,
            manifest: work.manifest,
            query: work.query,
            cursor: work.cursor + batch.length,
            total: work.total,
            notes: notes,
          );
          next.validate(target, input.windows);
          // Ensure every note's evidence fits the eventual frozen source budget.
          final requiredIds = notes.expand((n) => n.sourceIds).toSet();
          final requiredSources = chatPackGlobalSources([
            ...globalQuotes,
            for (final w in input.windows)
              if (requiredIds.contains(w.id)) w,
          ]);
          if (fitChatSources(requiredSources).length !=
              requiredSources.length) {
            throw const FormatException('Bukti catatan melebihi budget sumber');
          }
          _check(cancel);
          if (!await _chat.saveExploration(
            target.attemptRef,
            next,
            evidence: evidence,
          )) {
            return null;
          }
          work = next;
          onExplorationProgress?.call(work.cursor, work.total);
        }
        exploration = work;
        final ids = work.notes.expand((n) => n.sourceIds).toSet();
        selected = chatPackGlobalSources([
          ...globalQuotes,
          for (final w in input.windows)
            if (ids.contains(w.id)) w,
        ]);
        noteSourceIds = {
          for (final w in input.windows)
            if (ids.contains(w.id))
              w.id: selected
                  .firstWhere(
                    (s) =>
                        s.anchors.first.chapterId == w.anchors.first.chapterId,
                  )
                  .id,
        };
      } else if (!plan.needsClarification &&
          plan.strategy != ChatSearchStrategy.offTopic &&
          input.chunks.isNotEmpty) {
        final searched = <String>{...?saved?.searchedQueries};
        if (saved != null) {
          selected = _uniqueSources([
            ...input.quoted,
            for (final s in input.chunks)
              if (saved.selectedIds.contains(s.id)) s,
          ]);
        }
        var searchedThisTurn = 0;
        var queries =
            saved?.pendingQueries ??
            (plan.queries.isEmpty ? [plan.englishQuery] : plan.queries);
        var candidates = <ChatSource>[];
        ChatExploration searchCheckpoint(List<String> pending) =>
            ChatExploration(
              book: current,
              sessionId: target.sessionId,
              turnId: target.id,
              question: target.question,
              model: target.model,
              manifest: chatWindowManifest(input.chunks),
              query: plan.englishQuery,
              cursor: 0,
              total: input.chunks.length,
              notes: [],
              strategy: plan.strategy,
              searchedQueries: searched.toList(),
              pendingQueries: pending,
              selectedIds: selected.map((s) => s.id).toList(),
            );
        var searchWork = searchCheckpoint(queries);
        if (!await _chat.saveExploration(
          target.attemptRef,
          searchWork,
          evidence: selected,
        )) {
          return null;
        }
        // Initial search plus at most two requested follow-up rounds.
        for (var round = 0; round < 3; round++) {
          if (round > 0 && budget.bytes > 120000) break;
          final capacity = 64 - searched.length;
          final fresh = queries
              .where((q) => !searched.contains(q))
              .take(
                capacity < 3 - searchedThisTurn
                    ? capacity
                    : 3 - searchedThisTurn,
              )
              .toList();
          if (fresh.isEmpty) break;
          final rankings = await _rank(
            input.chunks,
            current,
            input.book.parserVersion,
            original,
            fresh,
            input.quoted,
            key,
            cancel,
            target,
            onIndexProgress,
            budget,
          );
          final found = chatFuseRanks(rankings, quoteSources: input.quoted);
          candidates = _uniqueSources([
            ...input.quoted,
            ...selected,
            ...found,
            ...candidates,
          ]).take(chatMaxCandidates).toList();
          validateChatSources(candidates, current, input.paragraphs);
          final forced = input.quoted.map((s) => s.id).toSet();
          final selectorUser = chatRetrievalUser(
            {
              'question': target.question,
              'history': history,
              'searchedQueries': searched.toList(),
              if (input.quoted.length == 1)
                'selectedSourceId': candidates.indexOf(input.quoted.single) + 1,
              'selectedSourceIds': [
                for (final (i, source) in candidates.indexed)
                  if (forced.contains(source.id)) i + 1,
              ],
              'candidates': [
                for (final (i, source) in candidates.indexed)
                  {
                    'id': i + 1,
                    'chapter': source.chapterTitle,
                    'paragraphStart': source.anchors.first.paragraphIndex,
                    'paragraphEnd': source.anchors.last.paragraphIndex,
                    'text': source.text,
                  },
              ],
            },
            chatSelectionSystem,
            chatSelectorBytes,
          );
          if (!await _chat.validateRetrieval(target.attemptRef, candidates)) {
            return null;
          }
          final raw = await _complete(
            key,
            target.model,
            chatSelectionSystem,
            selectorUser,
            600,
            cancel,
            budget,
          );
          selected = parseChatSelection(raw, candidates, input.quoted);
          searched.addAll(fresh);
          searchedThisTurn += fresh.length;
          queries = chatMissingQueries(raw)
              .where((q) => !searched.contains(q))
              .take(2)
              .toList();
          if (searched.length >= 64) queries = [];
          searchWork = searchCheckpoint(queries);
          if (!await _chat.saveExploration(
            target.attemptRef,
            searchWork,
            evidence: selected,
          )) {
            return null;
          }
          if (queries.isEmpty ||
              searchedThisTurn == 3 ||
              budget.elapsed.elapsed > const Duration(seconds: 100)) {
            break;
          }
        }
        exploration = searchWork;
        // Add adjacent windows after the direct evidence, without losing forced quotes.
        final neighbors = <ChatSource>[];
        for (final source in selected) {
          final i = input.chunks.indexOf(source);
          for (final j in [i - 1, i + 1]) {
            if (i >= 0 &&
                j >= 0 &&
                j < input.chunks.length &&
                input.chunks[j].anchors.first.chapterId ==
                    source.anchors.first.chapterId) {
              neighbors.add(input.chunks[j]);
            }
          }
        }
        selected = fitChatSources(_uniqueSources([...selected, ...neighbors]));
      }
      _check(cancel);
      final sourceIds = {
        for (final (i, source) in selected.indexed) source.id: 'S${i + 1}',
      };
      selected = [
        for (final (i, source) in selected.indexed)
          ChatSource(
            id: 'S${i + 1}',
            chapterTitle: source.chapterTitle,
            anchors: source.anchors,
          ),
      ];
      final prompt = buildChatPrompt(
        session: input.session,
        current: current,
        question: input.turn.question,
        beforeSequence: input.turn.sequence,
        history: input.history,
        sources: selected,
        paragraphs: input.paragraphs,
        title: input.book.title,
        author: input.book.author,
        quote: quote,
        exploration: exploration == null
            ? null
            : {
                ...(exploration.strategy == ChatSearchStrategy.global
                    ? exploration.promptData
                    : {
                        'complete': exploration.complete,
                        'searchedQueries': exploration.searchedQueries,
                        'pendingQueries': exploration.pendingQueries,
                        'wholeBookExamined': false,
                      }),
                'notes': [
                  for (final n in exploration.notes)
                    {
                      'text': n.text,
                      'source_ids': {
                        for (final id in n.sourceIds)
                          sourceIds[noteSourceIds[id] ?? id]!,
                      }.toList(),
                    },
                ],
              },
      );
      budget.answer(prompt);
      // Repository rechecks live revision/hash/owner and freezes the exact set.
      if (!await _chat.prepareSources(input.turn.attemptRef, prompt.sources)) {
        return null;
      }
      _check(cancel);
      return PreparedChat._(
        _router,
        key,
        input.turn.model,
        prompt,
        current,
        input.paragraphs,
        exploration,
        () => !_disposed
            ? _chat.validatePrepared(input.turn.attemptRef, prompt.sources)
            : Future.value(false),
      );
    } on FormatException catch (e) {
      throw AiException(AiError.invalidResponse, detail: e.message);
    }
  }

  Future<String> _complete(
    String key,
    String model,
    String system,
    String user,
    int tokens,
    CancelToken? cancel,
    _ChatRetrievalBudget budget,
  ) async {
    _check(cancel);
    if (budget.guard != null && !await budget.guard!()) {
      throw StateError('Attempt penelusuran sudah berhenti');
    }
    _check(cancel);
    budget.completion(system, user, tokens);
    var result = '';
    var bytes = 0;
    await for (final delta in _router.chatStream(
      apiKey: key,
      model: model,
      system: system,
      user: user,
      maxTokens: tokens,
      cancel: cancel,
    )) {
      _check(cancel);
      bytes += utf8.encode(delta).length;
      if (bytes > chatPromptBytes) {
        throw const FormatException('Retrieval output budget');
      }
      result += delta;
    }
    return result;
  }

  void _embeddingBudget(List<String> input) {
    if (input.any((s) => s.isEmpty || utf8.encode(s).length > 8000) ||
        input.fold<int>(0, (n, s) => n + utf8.encode(s).length) >
            chatEmbeddingInputBytes) {
      throw const FormatException('Buku/query melebihi budget embedding');
    }
  }

  Future<List<List<ChatSource>>> _rank(
    List<ChatSource> chunks,
    ChatBookRef book,
    int parserVersion,
    String original,
    List<String> english,
    List<ChatSource> quoted,
    String key,
    CancelToken? cancel,
    ChatTurn target,
    void Function(int, int)? onProgress,
    _ChatRetrievalBudget budget,
  ) async {
    final previous = _indexTail;
    final done = Completer<void>();
    _indexTail = done.future;
    await previous;
    try {
      _check(cancel);
      return await _rankIndex(
        chunks,
        book,
        parserVersion,
        original,
        english,
        quoted,
        key,
        cancel,
        target,
        onProgress,
        budget,
      );
    } finally {
      done.complete();
    }
  }

  Future<List<List<ChatSource>>> _rankIndex(
    List<ChatSource> chunks,
    ChatBookRef book,
    int parserVersion,
    String original,
    List<String> english,
    List<ChatSource> quoted,
    String key,
    CancelToken? cancel,
    ChatTurn target,
    void Function(int, int)? onProgress,
    _ChatRetrievalBudget budget,
  ) async {
    Future<void> guard() async {
      _check(cancel);
      final b = await (_db.select(
        _db.books,
      )..where((b) => b.id.equals(book.bookId))).getSingleOrNull();
      final t = await (_db.select(
        _db.chatTurns,
      )..where((t) => t.id.equals(target.id))).getSingleOrNull();
      final session = await (_db.select(
        _db.chatSessions,
      )..where((s) => s.id.equals(target.sessionId))).getSingleOrNull();
      _check(cancel);
      if (session == null ||
          session.bookId != book.bookId ||
          session.contentRevision != book.contentRevision ||
          b == null ||
          b.contentRevision != book.contentRevision ||
          b.parserVersion != parserVersion ||
          t == null ||
          t.sessionId != target.sessionId ||
          t.attempt != target.attempt ||
          !ChatPhase.values.any((p) => p.name == t.phase && p.isRunning)) {
        throw StateError('Index attempt sudah tidak aktif');
      }
    }

    final store = ChatIndexRepository(_db);
    final manifest = chatTextHash(
      jsonEncode([
        for (final s in chunks)
          {
            'id': s.id,
            'chapter': s.chapterTitle,
            'anchors': [
              for (final a in s.anchors)
                [
                  a.chapterId,
                  a.paragraphIndex,
                  a.start,
                  a.end,
                  a.paragraphHash,
                ],
            ],
          },
      ]),
    );
    Future<List<List<ChatSource>>> run(ChatEmbeddingModel embedding) async {
      final ChatIndexKey indexKey = (
        book: book,
        parserVersion: parserVersion,
        chunkPolicyVersion: chatChunkPolicyVersion,
        embedding: embedding,
        queryTemplateVersion: chatQueryTemplateVersion,
      );
      final queries = [
        embedding == ChatEmbeddingModel.qwen8b
            ? original
            : original.substring(chatQueryPrefix.length),
        for (final query in english)
          '${embedding == ChatEmbeddingModel.qwen8b ? chatQueryPrefix : ''}$query',
      ];
      final documents = chunks.map((s) => s.text).toList();
      _embeddingBudget([...documents, ...queries]);
      if (_indexKey != indexKey ||
          _manifest != manifest ||
          _documents == null) {
        // Drop the previous book from RAM before loading/building this index.
        _documents = null;
        final cached = await store.load(
          indexKey,
          manifest,
          documents.length,
          guard,
        );
        final vectors = cached.vectors;
        onProgress?.call(vectors.length, documents.length);
        while (vectors.length < documents.length) {
          await guard();
          budget.embedding(documents.skip(vectors.length).take(64).toList());
          final batch = await _router.embeddings(
            apiKey: key,
            model: embedding,
            input: documents.skip(vectors.length).take(64).toList(),
            cancel: cancel,
          );
          await store.saveBatch(
            cached.id,
            vectors.length,
            batch,
            embedding.dimensions,
            guard,
          );
          vectors.addAll(batch);
          onProgress?.call(vectors.length, documents.length);
        }
        await guard();
        _indexKey = indexKey;
        _manifest = manifest;
        _documents = vectors;
      }
      final vectors = _documents!;
      await guard();
      budget.embedding(queries);
      final q = await _router.embeddings(
        apiKey: key,
        model: embedding,
        input: queries,
        cancel: cancel,
      );
      _check(cancel);
      final quoteIds = quoted.map((s) => s.id).toSet();
      return [
        chatDenseSearch(chunks, vectors, q[0], quoteIds: quoteIds),
        for (var i = 0; i < english.length; i++) ...[
          chatDenseSearch(chunks, vectors, q[i + 1], quoteIds: quoteIds),
          ChatLexicalIndex(chunks)
              .search(english[i], quoteIds: quoteIds, k: chatMaxCandidates),
        ],
      ];
    }

    try {
      return await run(ChatEmbeddingModel.qwen8b);
    } on AiException catch (e) {
      final status = e.status;
      final providerFailure =
          e.error == AiError.timeout ||
          e.error == AiError.network ||
          e.error == AiError.http &&
              status != null &&
              ([404, 408, 429].contains(status) ||
                  status >= 500 && status <= 599);
      if (!providerFailure) rethrow;
      _check(cancel);
      return run(ChatEmbeddingModel.openaiLarge);
    }
  }
}

Map<String, Object?> _source(ChatSource s) => {
  'id': s.id,
  'chapter': s.chapterTitle,
  'paragraphStart': s.anchors.first.paragraphIndex,
  'paragraphEnd': s.anchors.last.paragraphIndex,
  'text': s.text,
};

String _rangeKey(ChatSource s) => jsonEncode([
  for (final a in s.anchors)
    [a.chapterId, a.paragraphIndex, a.start, a.end, a.paragraphHash],
]);

List<ChatSource> _uniqueSources(List<ChatSource> sources) {
  final ranges = <String>{};
  return [
    for (final s in sources)
      if (ranges.add(_rangeKey(s))) s,
  ];
}

class _ChatRetrievalBudget {
  final elapsed = Stopwatch()..start();
  Future<bool> Function()? guard;
  int calls = 0, tokens = 0, bytes = 0, embeddings = 0, embeddingBytes = 0;
  void completion(String system, String user, int output) {
    calls++;
    tokens += output;
    bytes += utf8.encode(system).length + utf8.encode(user).length;
    if (calls > 7 ||
        tokens > 8000 ||
        bytes > 280000 ||
        elapsed.elapsed > const Duration(seconds: 150)) {
      throw const FormatException('Budget penelusuran habis');
    }
  }

  void answer(ChatPrompt prompt) =>
      completion(prompt.system, prompt.user, chatAnswerMaxTokens);
  void embedding(List<String> inputs) {
    embeddings++;
    embeddingBytes += inputs.fold(0, (n, s) => n + utf8.encode(s).length);
    if (embeddings > 70 ||
        embeddingBytes > 3200000 ||
        elapsed.elapsed > const Duration(seconds: 150)) {
      throw const FormatException(
        'Budget index/query habis; lanjutkan secara eksplisit',
      );
    }
  }
}

/// Raw draft is durable transport data; preview is provisional, answer is final.
class ChatStreamFrame {
  const ChatStreamFrame(this.draft, {this.answer, this.preview = const []});
  final String draft;
  final ChatAnswer? answer;
  final List<ChatAnswerBlock> preview;
}

class PreparedChat {
  PreparedChat._(
    this._router,
    this._key,
    this.model,
    this.prompt,
    this.book,
    this._paragraphs,
    this._exploration,
    this._validate,
  );
  final OpenRouterService _router;
  final String _key, model;
  final ChatPrompt prompt;
  final ChatBookRef book;
  final Map<ChatParagraphRef, ChatParagraph> _paragraphs;
  final Future<bool> Function() _validate;
  final ChatExploration? _exploration;
  bool _started = false;

  Stream<ChatStreamFrame> stream({CancelToken? cancel}) async* {
    if (_started) throw StateError('Request chat sudah dipakai');
    _started = true;
    if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
    try {
      if (!await _validate()) return;
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      final decoder = ChatAnswerDecoder(
        prompt: prompt,
        current: book,
        paragraphs: _paragraphs,
      );
      var validatedParts = 0;
      await for (final delta in _router.chatStream(
        apiKey: _key,
        model: model,
        system: prompt.system,
        user: prompt.user,
        cancel: cancel,
      )) {
        decoder.add(delta);
        final preview = decoder.preview.blocks;
        final citedParts = preview.where((b) => b.sources.isNotEmpty).length;
        if (citedParts > validatedParts) {
          if (!await _validate()) return;
          if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
        }
        validatedParts = citedParts;
        yield ChatStreamFrame(decoder.raw, preview: preview);
      }
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      if (!await _validate()) return;
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      var answer = decoder.finish();
      final work = _exploration;
      if (work != null && !work.complete) {
        if (answer.blocks.length >= 32) {
          throw const FormatException(
            'Jawaban terlalu panjang untuk catatan cakupan',
          );
        }
        answer = ChatAnswer(
          status: ChatAnswerStatus.partial,
          formatVersion: 2,
          blocks: [
            ...answer.blocks,
            ChatAnswerBlock(
              text: work.strategy == ChatSearchStrategy.global
                  ? 'Udah diperiksa ${work.cursor}/${work.total} potongan isi buku. Masih ada ${work.total - work.cursor} potongan yang belum diperiksa. Pakai Lanjutkan buat meneruskan penelusuran.'
                  : 'Masih ada ${work.pendingQueries.length} kebutuhan pencarian yang belum diperiksa. Pakai Lanjutkan buat meneruskan penelusuran.',
              kind: ChatAnswerKind.conversation,
              sources: [],
            ),
          ],
        );
      }
      yield ChatStreamFrame(decoder.raw, answer: answer);
    } on FormatException catch (e) {
      throw AiException(AiError.invalidResponse, detail: e.message);
    }
  }
}

final chatContextRepositoryProvider = Provider<ChatContextRepository>((ref) {
  final repo = ChatContextRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(chatRepositoryProvider),
    ref.watch(openRouterServiceProvider),
    ref.watch(apiKeyStoreProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});
