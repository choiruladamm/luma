import 'dart:async';

import 'package:dio/dio.dart';
import 'package:luma/data/repositories/chat_context_repository.dart';
import 'package:luma/data/repositories/chat_repository.dart';
import 'package:luma/domain/chat_budget.dart';
import 'package:luma/domain/chat_exploration.dart';
import 'package:luma/domain/chat_prompt.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book_chat.dart';

const lifecycleBook = (bookId: 1, contentRevision: 1);

class LifecycleRepo implements ChatRepository {
  ChatBookRef? current = lifecycleBook;
  final sessions = <int, ChatSession>{};
  final turns = <int, ChatTurn>{};
  final changes = StreamController<void>.broadcast();
  final books = StreamController<ChatBookRef?>.broadcast();
  Completer<void>? createGate;
  Object? createError;
  Object? finalizeError;
  Completer<void>? finalizeGate;
  int creates = 0, retries = 0, opened = 0;
  int? last;
  final finalized = <({ChatAttemptRef ref, ChatPhase phase, String draft})>[];
  bool disposed = false;
  final at = DateTime.utc(2026, 10, 28);

  @override
  Future<int> recoverInterrupted() async => 0;
  @override
  Stream<ChatBookRef?> watchBook(int bookId) async* {
    yield current;
    yield* books.stream;
  }

  void revision(ChatBookRef? ref) {
    current = ref;
    books.add(ref);
  }

  List<ChatTurn> sessionTurns(int sessionId) =>
      turns.values.where((t) => t.sessionId == sessionId).toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
  @override
  Stream<List<ChatSession>> watchSessions(int bookId) => Stream.multi((sink) {
    List<ChatSession> snapshot() =>
        sessions.values.where((s) => s.book.bookId == bookId).toList();
    sink.add(snapshot());
    final sub = changes.stream.listen((_) => sink.add(snapshot()));
    sink.onCancel = sub.cancel;
  });
  @override
  Stream<List<ChatTurn>> watchTurns(int bookId, int sessionId) => Stream.multi((
    sink,
  ) {
    sink.add(sessionTurns(sessionId));
    final sub = changes.stream.listen((_) => sink.add(sessionTurns(sessionId)));
    sink.onCancel = sub.cancel;
  });
  @override
  Future<ChatSession?> session(int bookId, int sessionId) async =>
      sessions[sessionId]?.book.bookId == bookId ? sessions[sessionId] : null;
  @override
  Future<ChatSession?> sessionForQuote(ChatQuote quote) async => null;
  @override
  Future<ChatSession?> lastOpenedSession(int bookId) async =>
      last == null ? null : session(bookId, last!);
  @override
  Future<void> markOpened(int bookId, int sessionId) async {
    last = sessionId;
    opened++;
  }

  @override
  Future<ChatTurn> createFirstTurn(
    ChatBookRef book, {
    required String question,
    required String model,
    required int promptVersion,
    ChatQuote? quote,
  }) async {
    creates++;
    await createGate?.future;
    if (createError != null) throw createError!;
    final id = sessions.length + 1;
    sessions[id] = ChatSession(
      id: id,
      book: book,
      title: chatTitle(question, automatic: true),
      manualTitle: false,
      createdAt: at,
      updatedAt: at,
    );
    last = id;
    return _insert(book, id, question, model, promptVersion, quote);
  }

  ChatTurn _insert(
    ChatBookRef book,
    int sessionId,
    String question,
    String model,
    int promptVersion,
    ChatQuote? quote,
  ) {
    if (sessionTurns(sessionId).any((t) => t.phase.isRunning)) {
      throw StateError('pending');
    }
    final turn = ChatTurn(
      id: turns.length + 1,
      sessionId: sessionId,
      book: book,
      sequence: sessionTurns(sessionId).length,
      question: question,
      createdAt: at,
      updatedAt: at,
      phase: ChatPhase.preparing,
      model: model,
      promptVersion: promptVersion,
      quote: quote,
    );
    turns[turn.id] = turn;
    changes.add(null);
    return turn;
  }

  @override
  Future<ChatTurn> appendTurn(
    ChatBookRef book,
    int sessionId, {
    required String question,
    required String model,
    required int promptVersion,
    ChatQuote? quote,
  }) async => _insert(book, sessionId, question, model, promptVersion, quote);
  ChatTurn? owned(ChatAttemptRef ref) {
    final t = turns[ref.turnId];
    if (disposed ||
        current != ref.book ||
        sessions[ref.sessionId] == null ||
        t == null ||
        !t.accepts(ref, current!)) {
      return null;
    }
    return t;
  }

  ChatTurn update(
    ChatTurn t, {
    ChatPhase? phase,
    String? draft,
    ChatAnswer? answer,
    AiError? error,
    int? httpStatus,
  }) => ChatTurn(
    id: t.id,
    sessionId: t.sessionId,
    book: t.book,
    sequence: t.sequence,
    question: t.question,
    createdAt: t.createdAt,
    updatedAt: at,
    phase: phase ?? t.phase,
    model: t.model,
    promptVersion: t.promptVersion,
    attempt: t.attempt,
    quote: t.quote,
    draft: draft ?? t.draft,
    answer: answer,
    error: error,
    httpStatus: httpStatus,
  );
  @override
  Future<bool> prepareSources(
    ChatAttemptRef ref,
    List<ChatSource> sources,
  ) async {
    final t = owned(ref);
    if (t == null) return false;
    turns[t.id] = update(t, phase: ChatPhase.waiting);
    changes.add(null);
    return true;
  }

  @override
  Future<bool> checkpoint(
    ChatAttemptRef ref, {
    required String draft,
    required ChatPhase phase,
  }) async {
    final t = owned(ref);
    if (t == null || !draft.startsWith(t.draft)) return false;
    turns[t.id] = update(t, draft: draft, phase: phase);
    changes.add(null);
    return true;
  }

  @override
  Future<bool> finalize(
    ChatAttemptRef ref, {
    required ChatPhase phase,
    String? draft,
    ChatAnswer? answer,
    AiError? error,
    int? httpStatus,
  }) async {
    await finalizeGate?.future;
    if (finalizeError != null) throw finalizeError!;
    final t = owned(ref);
    if (t == null) return false;
    finalized.add((ref: ref, phase: phase, draft: draft ?? t.draft));
    turns[t.id] = update(
      t,
      phase: phase,
      draft: draft,
      answer: answer,
      error: error,
      httpStatus: httpStatus,
    );
    changes.add(null);
    return true;
  }

  @override
  Future<ChatTurn> retry(
    ChatAttemptRef ref, {
    required String model,
    required int promptVersion,
  }) async {
    retries++;
    final t = turns[ref.turnId]!;
    final next = t.retry(
      current: current!,
      isLatest: sessionTurns(t.sessionId).last.id == t.id,
      at: at,
      model: model,
      promptVersion: promptVersion,
    );
    turns[t.id] = next;
    changes.add(null);
    return next;
  }

  @override
  Future<ChatSession?> deleteSession(int bookId, int sessionId) async {
    sessions.remove(sessionId);
    turns.removeWhere((_, t) => t.sessionId == sessionId);
    if (last == sessionId) last = sessions.keys.lastOrNull;
    changes.add(null);
    return lastOpenedSession(bookId);
  }

  @override
  Future<void> rename(ChatBookRef book, int sessionId, String title) async {
    final s = sessions[sessionId]!;
    sessions[sessionId] = ChatSession(
      id: s.id,
      book: s.book,
      title: chatTitle(title),
      manualTitle: true,
      createdAt: s.createdAt,
      updatedAt: at,
      scrollAnchor: s.scrollAnchor,
    );
    changes.add(null);
  }

  @override
  Future<void> saveScrollAnchor(
    int bookId,
    int sessionId,
    ChatScrollAnchor? anchor,
  ) async {
    final s = sessions[sessionId]!;
    sessions[sessionId] = ChatSession(
      id: s.id,
      book: s.book,
      title: s.title,
      manualTitle: s.manualTitle,
      createdAt: s.createdAt,
      updatedAt: at,
      scrollAnchor: anchor,
    );
    changes.add(null);
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(changes.close());
    unawaited(books.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LifecyclePrepared implements PreparedChat {
  final frames = StreamController<ChatStreamFrame>();
  @override
  final book = lifecycleBook;
  @override
  final model = 'model';
  @override
  final prompt = ChatPrompt(user: '{}', sources: [], historyTurnIds: []);
  @override
  Stream<ChatStreamFrame> stream({CancelToken? cancel}) => frames.stream;
}

class LifecycleContext implements ChatContextRepository {
  LifecycleContext(this.repo);
  final LifecycleRepo repo;
  @override
  final tokenBudget = chatQuestionTokens;
  @override
  final deadline = chatQuestionDeadline;
  Completer<void>? modelGate, prepareGate;
  AiException? error;
  int calls = 0, models = 0;
  final prepared = <LifecyclePrepared>[];
  final cancels = <CancelToken?>[];
  final readingChapters = <int?>[];
  final progressSinks = <void Function(ChatExplorationProgress)?>[];
  final answerNowChecks = <bool Function()?>[];
  @override
  Future<String> model() async {
    models++;
    await modelGate?.future;
    return 'model';
  }

  @override
  Future<PreparedChat?> prepare(
    ChatTurn target, {
    CancelToken? cancel,
    int? readingChapterId,
    void Function(int, int)? onIndexProgress,
    void Function(ChatExplorationProgress)? onExplorationProgress,
    bool Function()? answerNow,
  }) async {
    calls++;
    progressSinks.add(onExplorationProgress);
    answerNowChecks.add(answerNow);
    readingChapters.add(readingChapterId);
    cancels.add(cancel);
    await prepareGate?.future;
    if (error != null) throw error!;
    if (!await repo.prepareSources(target.attemptRef, [])) return null;
    final next = LifecyclePrepared();
    prepared.add(next);
    return next;
  }

  @override
  void dispose() {
    for (final p in prepared) {
      unawaited(p.frames.close());
    }
  }
}
