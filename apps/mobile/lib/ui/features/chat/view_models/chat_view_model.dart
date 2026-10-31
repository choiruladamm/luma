import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../../../../data/repositories/chat_context_repository.dart';
import '../../../../data/repositories/chat_repository.dart';
import '../../../../data/services/chat_lifecycle.dart';
import '../../../../domain/chat_prompt.dart';
import '../../../../domain/chat_exploration.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/book_chat.dart';
import '../../reader/view_models/reader_view_model.dart' show GroupAiStream;

const _unchanged = Object();

class ChatState {
  ChatState({
    this.book,
    this.activeSession,
    this.draft = '',
    this.selectedQuote,
    List<ChatTurn> turns = const [],
    this.phase,
    this.preview,
    this.error,
    this.problem,
    this.loading = true,
    this.changingSession = false,
    this.scrollAnchor,
    this.indexProgress,
    this.explorationProgress,
  }) : turns = List.unmodifiable(turns);

  final ({int completed, int total})? indexProgress, explorationProgress;
  bool get canContinue =>
      !loading &&
      !busy &&
      !readOnly &&
      turns.isNotEmpty &&
      chatCanContinue(turns.last);
  final ChatBookRef? book;
  final ChatSession? activeSession;
  final String draft;
  final ChatQuote? selectedQuote;
  final List<ChatTurn> turns;
  final ChatPhase? phase;
  final ({ChatAttemptRef attempt, List<ChatAnswerBlock> blocks})? preview;
  final AiException? error;
  final String? problem;
  final bool loading, changingSession;
  final ChatScrollAnchor? scrollAnchor;
  bool get archived =>
      activeSession != null && book != null && activeSession!.isArchived(book!);
  bool get readOnly =>
      book == null || archived || (activeSession?.invalid ?? false);
  bool get busy => changingSession || (phase?.isRunning ?? false);
  bool get canSend => !loading && !busy && !readOnly && draft.trim().isNotEmpty;
  bool get canRetry =>
      !loading &&
      !busy &&
      !readOnly &&
      turns.isNotEmpty &&
      [
        ChatPhase.failed,
        ChatPhase.cut,
        ChatPhase.stopped,
        ChatPhase.interrupted,
      ].contains(turns.last.phase);

  ChatState copyWith({
    Object? book = _unchanged,
    Object? activeSession = _unchanged,
    String? draft,
    Object? selectedQuote = _unchanged,
    List<ChatTurn>? turns,
    Object? phase = _unchanged,
    Object? preview = _unchanged,
    Object? error = _unchanged,
    Object? problem = _unchanged,
    bool? loading,
    bool? changingSession,
    Object? scrollAnchor = _unchanged,
    Object? indexProgress = _unchanged,
    Object? explorationProgress = _unchanged,
  }) => ChatState(
    explorationProgress: identical(explorationProgress, _unchanged)
        ? this.explorationProgress
        : explorationProgress as ({int completed, int total})?,
    indexProgress: identical(indexProgress, _unchanged)
        ? this.indexProgress
        : indexProgress as ({int completed, int total})?,
    book: identical(book, _unchanged) ? this.book : book as ChatBookRef?,
    activeSession: identical(activeSession, _unchanged)
        ? this.activeSession
        : activeSession as ChatSession?,
    draft: draft ?? this.draft,
    selectedQuote: identical(selectedQuote, _unchanged)
        ? this.selectedQuote
        : selectedQuote as ChatQuote?,
    turns: turns ?? this.turns,
    preview: identical(preview, _unchanged)
        ? this.preview
        : preview as ({ChatAttemptRef attempt, List<ChatAnswerBlock> blocks})?,
    phase: identical(phase, _unchanged) ? this.phase : phase as ChatPhase?,
    error: identical(error, _unchanged) ? this.error : error as AiException?,
    problem: identical(problem, _unchanged) ? this.problem : problem as String?,
    loading: loading ?? this.loading,
    changingSession: changingSession ?? this.changingSession,
    scrollAnchor: identical(scrollAnchor, _unchanged)
        ? this.scrollAnchor
        : scrollAnchor as ChatScrollAnchor?,
  );
}

final chatSessionsProvider = StreamProvider.autoDispose
    .family<List<ChatSession>, int>(
      (ref, bookId) => ref.watch(chatRepositoryProvider).watchSessions(bookId),
    );

/// One controller per book route. Entry quotes are applied explicitly via launch,
/// never by rebuilding the provider or changing a family key.
class ChatViewModel extends Notifier<ChatState> {
  ChatViewModel(this.bookId);
  final int bookId;
  static const retrievalTimeout = Duration(minutes: 3);
  late _ChatLifetime _life;

  bool _live(_ChatLifetime life) => life.alive && identical(life, _life);
  bool _running(_ChatLifetime life, _ChatRun run) =>
      _live(life) && run.live && identical(life.run, run);

  @override
  ChatState build() {
    final life = _life = _ChatLifetime(
      ref.watch(chatRepositoryProvider),
      ref.watch(chatContextRepositoryProvider),
    );
    final chatLifecycle = ref.watch(chatLifecycleProvider);
    final unregister = chatLifecycle.register(bookId, () async {
      await _stop(life);
      if (life.flushError != null) throw life.flushError!;
    });
    final lifecycle = AppLifecycleListener(
      onStateChange: (appState) {
        if (_live(life) && appState != AppLifecycleState.resumed) {
          unawaited(_stop(life));
        }
      },
    );
    ref.onDispose(() {
      life.alive = false;
      lifecycle.dispose();
      unawaited(life.books?.cancel());
      unawaited(life.sessions?.cancel());
      unawaited(life.turns?.cancel());
      // Keep pending disposal flushes registered until restore can await them.
      unawaited(
        _stop(life).then((_) {
          if (life.flushError == null) unregister();
        }),
      );
    });
    unawaited(life.hydration = _hydrate(life));
    return ChatState();
  }

  Future<void> _hydrate(_ChatLifetime life) async {
    try {
      await life.repo.recoverInterrupted();
      if (!_live(life)) return;
      life.books = life.repo.watchBook(bookId).listen((book) {
        if (!_live(life)) return;
        final changed = !state.loading && state.book != book;
        state = state.copyWith(book: book);
        if (changed) {
          unawaited(_stop(life));
          state = state.copyWith(
            selectedQuote: null,
            problem: book == null
                ? 'Buku ini sudah dihapus.'
                : 'Isi buku berubah. Mulai obrolan baru untuk lanjut.',
          );
        }
      }, onError: (Object e) => _problem(life, e));
      final book = await life.repo.watchBook(bookId).first;
      if (!_live(life)) return;
      state = state.copyWith(book: book);
      final last = await life.repo.lastOpenedSession(bookId);
      if (!_live(life)) return;
      await _activate(life, last);
      if (!_live(life)) return;
      state = state.copyWith(
        loading: false,
        problem: book == null ? 'Buku ini sudah dihapus.' : null,
      );
      life.sessions = life.repo.watchSessions(bookId).listen((sessions) {
        if (!_live(life) || life.session == null) return;
        final matches = sessions.where((s) => s.id == life.session!.id);
        if (matches.isNotEmpty) {
          life.session = matches.first;
          state = state.copyWith(
            activeSession: life.session,
            problem: life.session!.invalid
                ? 'Riwayat sesi ini rusak. Lo bisa hapus sesi ini.'
                : state.problem,
          );
        } else {
          unawaited(
            _change(life, () async {
              await _activate(life, await life.repo.lastOpenedSession(bookId));
            }),
          );
        }
      }, onError: (Object e) => _problem(life, e));
    } catch (e) {
      _problem(life, e);
      if (_live(life)) state = state.copyWith(loading: false);
    }
  }

  void _problem(_ChatLifetime life, Object e) {
    if (_live(life)) {
      state = state.copyWith(
        problem: 'Obrolan belum bisa dibuka. Coba buka lagi.',
      );
    }
  }

  Future<void> _activate(_ChatLifetime life, ChatSession? session) async {
    if (!_live(life)) return;
    final selection = ++life.selection;
    // Selection fences old read-only callbacks; cancellation must not block navigation.
    unawaited(life.turns?.cancel());
    life.session = session;
    life.anchor = session?.scrollAnchor;
    state = state.copyWith(
      activeSession: session,
      turns: [],
      preview: null,
      draft: '',
      selectedQuote: null,
      phase: life.run == null ? null : state.phase,
      error: null,
      problem: session?.invalid == true
          ? 'Riwayat sesi ini rusak. Lo bisa hapus sesi ini.'
          : null,
      scrollAnchor: life.anchor,
    );
    if (session == null) return;
    life.turns = life.repo.watchTurns(bookId, session.id).listen((turns) {
      if (!_live(life) || life.selection != selection) return;
      final last = turns.lastOrNull;
      final idle = life.run == null;
      state = state.copyWith(
        turns: turns,
        phase: idle ? last?.phase : state.phase,
        error: idle
            ? (last?.error == null
                  ? null
                  : AiException(last!.error!, status: last.httpStatus))
            : state.error,
      );
    }, onError: (Object e) => _problem(life, e));
  }

  void setDraft(String value) {
    if (!state.loading && !state.busy && !state.readOnly) {
      state = state.copyWith(draft: value, error: null);
    }
  }

  void removeQuote() {
    if (!state.busy) state = state.copyWith(selectedQuote: null);
  }

  void setScrollAnchor(ChatScrollAnchor anchor) {
    _life.anchor = anchor;
    state = state.copyWith(scrollAnchor: anchor);
  }

  Future<void> _saveAnchor(_ChatLifetime life) async {
    final session = life.session, anchor = life.anchor;
    if (session != null && anchor != null) {
      await life.repo.saveScrollAnchor(bookId, session.id, anchor);
    }
  }

  Future<void> _change(_ChatLifetime life, Future<void> Function() action) {
    if (!_live(life)) return Future.value();
    final previous = life.transition ?? Future.value();
    final completed = Completer<void>();
    life.transition = completed.future;
    state = state.copyWith(changingSession: true);
    final stopped = _stop(life);
    return () async {
      try {
        await previous;
        await stopped;
        await life.hydration;
        if (_live(life)) await action();
      } catch (e) {
        _problem(life, e);
      } finally {
        completed.complete();
        if (_live(life) && identical(life.transition, completed.future)) {
          life.transition = null;
          state = state.copyWith(changingSession: false);
        }
      }
    }();
  }

  Future<void> openSession(int sessionId) {
    final life = _life;
    return _change(life, () async {
      final session = await life.repo.session(bookId, sessionId);
      if (session == null) throw StateError('Sesi sudah dihapus');
      if (!_live(life)) return;
      await life.repo.markOpened(bookId, sessionId);
      await _activate(life, session);
    });
  }

  Future<void> newSession() {
    final life = _life;
    return _change(life, () => _activate(life, null));
  }

  Future<void> launch(ChatLaunchContext context) {
    final life = _life;
    return _change(life, () async {
      if (context.book.bookId != bookId || context.book != state.book) {
        throw const FormatException('Entry buku berubah');
      }
      if (context.startsNewSession) {
        final existing = await life.repo.sessionForQuote(context.quote!);
        if (!_live(life)) return;
        if (existing != null) await life.repo.markOpened(bookId, existing.id);
        await _activate(life, existing);
        if (_live(life) && existing == null) {
          state = state.copyWith(selectedQuote: context.quote);
        }
      } else {
        await _activate(life, await life.repo.lastOpenedSession(bookId));
      }
    });
  }

  Future<void> deleteSession(int sessionId) {
    final life = _life;
    return _change(life, () async {
      final next = await life.repo.deleteSession(bookId, sessionId);
      if (life.session?.id == sessionId) await _activate(life, next);
    });
  }

  Future<void> rename(String title) async {
    final session = state.activeSession;
    if (session != null) await renameSession(session, title);
  }

  Future<bool> renameSession(ChatSession session, String title) async {
    final life = _life;
    if (session.book.bookId != bookId ||
        session.book != state.book ||
        session.invalid ||
        state.changingSession) {
      return false;
    }
    try {
      await life.repo.rename(session.book, session.id, title);
      return true;
    } catch (e) {
      _problem(life, e);
      return false;
    }
  }

  Future<void> send() {
    if (!state.canSend || _life.run != null) return Future.value();
    final String question;
    try {
      question = chatQuestion(state.draft);
    } on FormatException {
      state = state.copyWith(
        problem: 'Pertanyaan kosong atau terlalu panjang.',
      );
      return Future.value();
    }
    return _start(_life, question: question, quote: state.selectedQuote);
  }

  Future<void> continueExploration() {
    if (!state.canContinue || _life.run != null) return Future.value();
    return _start(_life, continuation: state.turns.last);
  }

  Future<void> retry() {
    if (!state.canRetry || _life.run != null) return Future.value();
    return _start(_life, retry: state.turns.last);
  }

  Future<void> _start(
    _ChatLifetime life, {
    String? question,
    ChatQuote? quote,
    ChatTurn? retry,
    ChatTurn? continuation,
  }) {
    if (!ref.read(chatLifecycleProvider).canStart(bookId)) {
      return Future.value();
    }
    final run = life.run =
        _ChatRun(); // Guard first-send before the first await.
    final book = state.book!, session = life.session;
    state = state.copyWith(
      phase: ChatPhase.preparing,
      error: null,
      problem: null,
    );
    _arm(life, run, retrievalTimeout);
    return _request(
      life,
      run,
      book,
      session,
      question,
      quote,
      retry,
      continuation,
    );
  }

  void _arm(_ChatLifetime life, _ChatRun run, Duration timeout) {
    run.clearTimers();
    run.timers.add(
      Timer(GroupAiStream.slowAfter, () {
        if (_running(life, run)) state = state.copyWith(phase: ChatPhase.slow);
      }),
    );
    run.timers.add(
      Timer(timeout, () {
        unawaited(
          _finish(
            life,
            run,
            phase: run.raw.isEmpty ? ChatPhase.failed : ChatPhase.cut,
            error: const AiException(AiError.timeout),
          ),
        );
      }),
    );
  }

  Future<void> _request(
    _ChatLifetime life,
    _ChatRun run,
    ChatBookRef book,
    ChatSession? session,
    String? question,
    ChatQuote? quote,
    ChatTurn? retry,
    ChatTurn? continuation,
  ) async {
    try {
      final model = await life.context.model();
      if (!run.live) return;
      final turn = continuation != null
          ? await life.repo.continueExploration(continuation, model: model)
          : retry != null
          ? await life.repo.retry(
              retry.attemptRef,
              model: model,
              promptVersion: chatPromptVersion,
            )
          : session == null
          ? await life.repo.createFirstTurn(
              book,
              question: question!,
              model: model,
              promptVersion: chatPromptVersion,
              quote: quote,
            )
          : await life.repo.appendTurn(
              book,
              session.id,
              question: question!,
              model: model,
              promptVersion: chatPromptVersion,
              quote: quote,
            );
      run.turn = turn;
      run.created.complete();
      if (!_running(life, run)) return;
      if (session == null) {
        final created = await life.repo.session(bookId, turn.sessionId);
        if (!_running(life, run)) return;
        await _activate(life, created);
      }
      if (!_running(life, run)) return;
      state = state.copyWith(
        draft: '',
        selectedQuote: null,
        phase: ChatPhase.retrieving,
        preview: null,
        indexProgress: null,
        explorationProgress: null,
      );
      if (!await life.repo.checkpoint(
        turn.attemptRef,
        draft: '',
        phase: ChatPhase.retrieving,
      )) {
        await _finish(life, run, phase: ChatPhase.interrupted);
        return;
      }
      if (!_running(life, run)) return;
      final prepared = await life.context.prepare(
        turn,
        cancel: run.cancel,
        onExplorationProgress: (completed, total) {
          if (_running(life, run)) {
            state = state.copyWith(
              explorationProgress: (completed: completed, total: total),
            );
          }
        },
        onIndexProgress: (completed, total) {
          if (_running(life, run)) {
            state = state.copyWith(
              indexProgress: (completed: completed, total: total),
            );
          }
        },
      );
      if (!_running(life, run)) return;
      if (prepared == null) {
        await _finish(life, run, phase: ChatPhase.interrupted);
        return;
      }
      state = state.copyWith(phase: ChatPhase.waiting);
      _arm(life, run, GroupAiStream.timeoutAfter);
      final iterator = run.iterator = StreamIterator(
        prepared.stream(cancel: run.cancel),
      );
      while (await iterator.moveNext()) {
        if (!_running(life, run)) return;
        final frame = iterator.current;
        run.raw = frame.draft;
        if (frame.answer != null) {
          await _finish(life, run, phase: ChatPhase.done, answer: frame.answer);
          return;
        }
        run.preview = frame.preview;
        if (run.raw.isEmpty) continue;
        run.clearTimers();
        if (state.phase != ChatPhase.writing) {
          state = state.copyWith(phase: ChatPhase.writing);
        }
        run.previewTimer ??= Timer(const Duration(milliseconds: 50), () {
          run.previewTimer = null;
          if (_running(life, run)) _publishPreview(run);
        });
        run.timers.add(
          Timer(GroupAiStream.stallAfter, () {
            unawaited(
              _finish(
                life,
                run,
                phase: ChatPhase.cut,
                error: const AiException(AiError.timeout),
              ),
            );
          }),
        );
        if (!await life.repo.checkpoint(
          turn.attemptRef,
          draft: run.raw,
          phase: ChatPhase.writing,
        )) {
          await _finish(life, run, phase: ChatPhase.interrupted);
          return;
        }
      }
      if (_running(life, run)) {
        await _finish(life, run, phase: ChatPhase.interrupted);
      }
    } catch (e) {
      if (e is AiException &&
          e.error == AiError.invalidResponse &&
          e.detail?.startsWith('Checkpoint') == true &&
          _live(life)) {
        state = state.copyWith(
          problem: 'Progres penelusuran sudah tidak cocok. Kirim pertanyaan baru buat mulai ulang.',
        );
      }
      if (e is FormatException && _live(life)) {
        state = state.copyWith(problem: e.message);
      }
      if (!run.created.isCompleted) run.created.complete();
      if (run.live) {
        await _finish(
          life,
          run,
          phase: run.raw.isEmpty ? ChatPhase.failed : ChatPhase.cut,
          error: _error(e),
        );
      }
    } finally {
      if (!run.created.isCompleted) run.created.complete();
    }
  }

  AiException _error(Object e) {
    if (e is AiException) return e;
    if (e is DioException) {
      return AiException(AiError.network, detail: e.type.name);
    }
    return const AiException(AiError.invalidResponse);
  }

  void _publishPreview(_ChatRun run) {
    final turn = run.turn;
    if (turn != null) {
      state = state.copyWith(
        preview: (attempt: turn.attemptRef, blocks: run.preview),
      );
    }
  }

  Future<void> _finish(
    _ChatLifetime life,
    _ChatRun run, {
    required ChatPhase phase,
    AiException? error,
    ChatAnswer? answer,
  }) {
    if (run.terminal != null) return run.terminal!;
    run.live = false;
    run.previewTimer?.cancel();
    run.previewTimer = null;
    run.preview = phase == ChatPhase.done
        ? run.preview
        : [
            for (final b in run.preview)
              ChatAnswerBlock(text: b.text, kind: b.kind, sources: []),
          ];
    if (_live(life)) _publishPreview(run);
    run.cancel.cancel();
    run.clearTimers();
    unawaited(run.iterator?.cancel());
    return run.terminal = () async {
      try {
        await run.created.future;
        final turn = run.turn;
        if (turn != null) {
          final accepted = await life.repo.finalize(
            turn.attemptRef,
            phase: phase,
            draft: run.raw,
            answer: answer,
            error: error?.error,
            httpStatus: error?.status,
          );
          if (accepted) {
            life.flushError = null;
            if (answer != null) {
              run.preview = answer.blocks;
              if (_live(life)) _publishPreview(run);
            }
          }
          if (accepted &&
              _live(life) &&
              life.session == null &&
              life.transition == null) {
            final session = await life.repo.session(bookId, turn.sessionId);
            if (_live(life) &&
                life.session == null &&
                life.transition == null &&
                session != null) {
              await _activate(life, session);
            }
          }
          if (!accepted) {
            run.preview = [
              for (final b in run.preview)
                ChatAnswerBlock(text: b.text, kind: b.kind, sources: []),
            ];
            if (_live(life)) _publishPreview(run);
            phase = ChatPhase.interrupted;
            error = null;
          }
        }
      } catch (e) {
        life.flushError = e;
        run.preview = [
          for (final b in run.preview)
            ChatAnswerBlock(text: b.text, kind: b.kind, sources: []),
        ];
        if (_live(life)) _publishPreview(run);
        phase = ChatPhase.failed;
        error = _error(e);
        _problem(life, e);
      } finally {
        if (identical(life.run, run)) life.run = null;
        if (_live(life)) state = state.copyWith(phase: phase, error: error);
      }
    }();
  }

  Future<void> _stop(_ChatLifetime life) async {
    final run = life.run;
    if (run != null) await _finish(life, run, phase: ChatPhase.stopped);
    try {
      await _saveAnchor(life);
    } catch (e) {
      _problem(life, e);
    }
  }

  /// Also used for back/background before navigation or DB replacement.
  Future<void> stop() => _stop(_life);
}

class _ChatRun {
  bool live = true;
  final cancel = CancelToken();
  final created = Completer<void>();
  ChatTurn? turn;
  String raw = '';
  List<ChatAnswerBlock> preview = const [];
  Timer? previewTimer;
  Future<void>? terminal;
  StreamIterator<ChatStreamFrame>? iterator;
  final timers = <Timer>[];
  void clearTimers() {
    for (final timer in timers) {
      timer.cancel();
    }
    timers.clear();
  }
}

class _ChatLifetime {
  _ChatLifetime(this.repo, this.context);
  final ChatRepository repo;
  final ChatContextRepository context;
  bool alive = true;
  Object? flushError;
  late Future<void> hydration;
  int selection = 0;
  ChatSession? session;
  ChatScrollAnchor? anchor;
  _ChatRun? run;
  Future<void>? transition;
  StreamSubscription<ChatBookRef?>? books;
  StreamSubscription<List<ChatSession>>? sessions;
  StreamSubscription<List<ChatTurn>>? turns;
}

final chatViewModelProvider = NotifierProvider.autoDispose
    .family<ChatViewModel, ChatState, int>(ChatViewModel.new);
