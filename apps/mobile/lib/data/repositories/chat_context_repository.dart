import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chat_prompt.dart';
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
          paragraphs: paragraphs,
          history: turns,
          quoted: quoted,
          preflight: preflight,
        );
      });
      _check(cancel);
      if (input == null) return null;
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
      // Preflight all known embedding inputs, including the original query.
      final original = chatEmbeddingQuery(
        input.turn.question,
        history,
        quote,
        ChatEmbeddingModel.qwen8b,
      );
      _embeddingBudget([...input.chunks.map((s) => s.text), original]);
      final plan = parseChatQueryPlan(
        await _complete(
          key,
          input.turn.model,
          chatRewriteSystem,
          rewriteUser,
          256,
          cancel,
        ),
      );
      _check(cancel);
      var selected = input.quoted;
      if (!plan.needsClarification && input.chunks.isNotEmpty) {
        final english = plan.englishQuery;
        final rankings = await _rank(
          input.chunks,
          current,
          input.book.parserVersion,
          original,
          english,
          input.quoted,
          key,
          cancel,
          target,
          onIndexProgress,
        );
        final candidates = chatFuseRanks(rankings, quoteSources: input.quoted);
        validateChatSources(candidates, current, input.paragraphs);
        final forced = input.quoted.map((s) => s.id).toSet();
        final selectorUser = chatRetrievalUser(
          {
            'question': input.turn.question,
            'history': history,
            if (input.quoted.length == 1)
              'selectedSourceId': candidates.indexOf(input.quoted.single) + 1,
            if (input.quoted.length > 1)
              'selectedSourceIds': [
                for (final (i, s) in candidates.indexed)
                  if (forced.contains(s.id)) i + 1,
              ],
            'candidates': [
              for (final (i, s) in candidates.indexed)
                {
                  'id': i + 1,
                  'chapter': s.chapterTitle,
                  'paragraphStart': s.anchors.first.paragraphIndex,
                  'paragraphEnd': s.anchors.last.paragraphIndex,
                  'text': s.text,
                },
            ],
          },
          chatSelectionSystem,
          chatSelectorBytes,
        );
        selected = parseChatSelection(
          await _complete(
            key,
            input.turn.model,
            chatSelectionSystem,
            selectorUser,
            256,
            cancel,
          ),
          candidates,
          input.quoted,
        );
      }
      _check(cancel);
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
      );
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
        plan.needsClarification || selected.isEmpty,
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
  ) async {
    _check(cancel);
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
    String english,
    List<ChatSource> quoted,
    String key,
    CancelToken? cancel,
    ChatTurn target,
    void Function(int, int)? onProgress,
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
    String english,
    List<ChatSource> quoted,
    String key,
    CancelToken? cancel,
    ChatTurn target,
    void Function(int, int)? onProgress,
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
        '${embedding == ChatEmbeddingModel.qwen8b ? chatQueryPrefix : ''}$english',
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
        chatDenseSearch(chunks, vectors, q[1], quoteIds: quoteIds),
        ChatLexicalIndex(chunks)
            .search(english, quoteIds: quoteIds, k: chatMaxCandidates),
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

/// Draft is raw checkpoint data; only the final frame exposes an answer/sources.
class ChatStreamFrame {
  const ChatStreamFrame(this.draft, {this.answer});
  final String draft;
  final ChatAnswer? answer;
}

class PreparedChat {
  PreparedChat._(
    this._router,
    this._key,
    this.model,
    this.prompt,
    this.book,
    this._paragraphs,
    this._noSource,
    this._validate,
  );
  final OpenRouterService _router;
  final String _key, model;
  final ChatPrompt prompt;
  final ChatBookRef book;
  final Map<ChatParagraphRef, ChatParagraph> _paragraphs;
  final bool _noSource;
  final Future<bool> Function() _validate;
  bool _started = false;

  Stream<ChatStreamFrame> stream({CancelToken? cancel}) async* {
    if (_started) throw StateError('Request chat sudah dipakai');
    _started = true;
    if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
    try {
      if (!await _validate()) return;
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      if (_noSource) {
        yield ChatStreamFrame(
          '',
          answer: ChatAnswer(status: ChatAnswerStatus.notFound, blocks: []),
        );
        return;
      }
      final decoder = ChatAnswerDecoder(
        prompt: prompt,
        current: book,
        paragraphs: _paragraphs,
      );
      await for (final delta in _router.chatStream(
        apiKey: _key,
        model: model,
        system: prompt.system,
        user: prompt.user,
        cancel: cancel,
      )) {
        decoder.add(delta);
        yield ChatStreamFrame(decoder.raw);
      }
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      if (!await _validate()) return;
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      yield ChatStreamFrame(decoder.raw, answer: decoder.finish());
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
