import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/chat_context_repository.dart';
import 'package:luma/data/repositories/chat_repository.dart';
import 'package:luma/data/services/chat_lifecycle.dart';
import 'package:luma/domain/models/ai_reply.dart';
import 'package:luma/domain/models/book_chat.dart';
import 'package:luma/ui/features/chat/view_models/chat_view_model.dart';

import '../support/chat_lifecycle_fakes.dart';

// Stream cancellation/Riverpod may schedule a zero-duration event as well as microtasks.
void pump(FakeAsync time) {
  time.flushMicrotasks();
  time.elapse(Duration.zero);
  time.flushMicrotasks();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LifecycleRepo repo;
  late LifecycleContext context;
  late ProviderContainer container;
  final provider = chatViewModelProvider(1);
  ChatState state() => container.read(provider);
  ChatViewModel vm() => container.read(provider.notifier);
  void open(FakeAsync time) {
    repo = LifecycleRepo();
    context = LifecycleContext(repo);
    container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        chatContextRepositoryProvider.overrideWithValue(context),
      ],
    );
    container.listen(provider, (_, _) {}, fireImmediately: true);
    pump(time);
  }

  void close(FakeAsync time) {
    container.dispose();
    pump(time);
    context.dispose();
    repo.dispose();
    pump(time);
    expect(time.nonPeriodicTimerCount, 0);
  }

  void send(FakeAsync time, [String text = 'Pertanyaan?']) {
    vm().setDraft(text);
    unawaited(vm().send());
    pump(time);
  }

  void delta(FakeAsync time, String raw) {
    context.prepared.last.frames.add(ChatStreamFrame(raw));
    pump(time);
  }

  void done(FakeAsync time) {
    context.prepared.last.frames.add(
      ChatStreamFrame(
        '',
        answer: ChatAnswer(status: ChatAnswerStatus.notFound, blocks: []),
      ),
    );
    pump(time);
  }

  test('invalid final and storage failure retain draft but revoke provisional citations', () {
    for (final storageFailure in [false, true]) {
      fakeAsync((time) {
        open(time);
        send(time);
        final source = ChatSource(
          id: 'S1',
          chapterTitle: 'Bab',
          anchors: [
            SourceAnchor(
              book: lifecycleBook,
              chapterId: 1,
              paragraphIndex: 0,
              start: 0,
              end: 1,
              paragraphHash: 'h',
              snapshot: 'x',
            ),
          ],
        );
        final block = ChatAnswerBlock(text: 'Draf terbaca', sources: [source]);
        context.prepared.last.frames.add(
          ChatStreamFrame('raw', preview: [block]),
        );
        pump(time);
        time.elapse(const Duration(milliseconds: 50));
        expect(state().preview!.blocks.single.sources, isNotEmpty);
        if (storageFailure) {
          repo.finalizeError = StateError('disk');
          context.prepared.last.frames.add(
            ChatStreamFrame(
              'raw',
              answer: ChatAnswer(
                status: ChatAnswerStatus.answered,
                blocks: [block],
              ),
            ),
          );
        } else {
          context.prepared.last.frames.addError(
            const AiException(AiError.invalidResponse),
          );
        }
        pump(time);
        expect(state().preview!.blocks.single.text, 'Draf terbaca');
        expect(state().preview!.blocks.single.sources, isEmpty);
        expect(
          state().phase,
          storageFailure ? ChatPhase.failed : ChatPhase.cut,
        );
        expect(state().turns.every((t) => !t.trustedHistory), true);
        repo.finalizeError = null;
        close(time);
      });
    }
  });

  test(
    'repair frames show a status, keep the old preview until new text, and reset per send',
    () => fakeAsync((time) {
      open(time);
      send(time);
      final attempt = context.prepared.last;
      attempt.frames.add(
        ChatStreamFrame(
          '{"parts":[{"text":"Draf',
          preview: [ChatAnswerBlock(text: 'Draf', sources: [])],
        ),
      );
      pump(time);
      time.elapse(const Duration(milliseconds: 50));
      expect(state().preview!.blocks.single.text, 'Draf');
      expect(state().repairAttempt, 0);
      attempt.frames.add(
        ChatStreamFrame(
          '{"parts":[{"text":"Draf\n',
          preview: [ChatAnswerBlock(text: 'Draf', sources: [])],
          repair: 1,
          repairReason: 'ID sumber tidak valid',
        ),
      );
      pump(time);
      expect(state().repairAttempt, 1);
      expect(state().phase, ChatPhase.waiting);
      expect(state().preview!.blocks.single.text, 'Draf');
      // The repaired stream appends to the durable draft; no empty flash.
      attempt.frames.add(
        const ChatStreamFrame('{"parts":[{"text":"Draf\n{', repair: 1),
      );
      pump(time);
      time.elapse(const Duration(milliseconds: 50));
      expect(state().preview!.blocks.single.text, 'Draf');
      attempt.frames.add(
        ChatStreamFrame(
          '{"parts":[{"text":"Draf\n{"parts":[{"text":"Draf baru',
          preview: [ChatAnswerBlock(text: 'Draf baru', sources: [])],
          repair: 1,
        ),
      );
      pump(time);
      time.elapse(const Duration(milliseconds: 50));
      expect(state().preview!.blocks.single.text, 'Draf baru');
      expect(state().phase, ChatPhase.writing);
      done(time);
      expect(state().phase, ChatPhase.done);
      expect(state().repairAttempt, 1); // visible until the next send
      send(time, 'Lagi?');
      expect(state().repairAttempt, 0);
      close(time);
    }),
  );

  test(
    'saved notes show as a provisional draft during reading; Jawab sekarang flags the run once',
    () => fakeAsync((time) {
      open(time);
      send(time);
      final sink = context.progressSinks.last!;
      sink((completed: 0, total: 10, label: 'Book I › II', notes: const []));
      pump(time);
      expect(state().explorationProgress!.label, 'Book I › II');
      expect(state().preview, isNull);
      sink((
        completed: 4,
        total: 10,
        label: 'Book I › III',
        notes: const [
          (text: 'Catatan satu', sourceIds: ['S1']),
        ],
      ));
      pump(time);
      time.elapse(const Duration(milliseconds: 50));
      expect(state().preview!.blocks.single.text, 'Catatan satu');
      expect(state().preview!.blocks.single.sources, isEmpty);
      expect(state().preview!.blocks.single.kind, ChatAnswerKind.conversation);
      // Empty answer frames keep the notes visible until real text arrives.
      context.prepared.last.frames.add(const ChatStreamFrame('{'));
      pump(time);
      time.elapse(const Duration(milliseconds: 50));
      expect(state().preview!.blocks.single.text, 'Catatan satu');
      context.prepared.last.frames.add(
        ChatStreamFrame(
          '{"parts":[{"text":"Jawaban',
          preview: [ChatAnswerBlock(text: 'Jawaban', sources: [])],
        ),
      );
      pump(time);
      time.elapse(const Duration(milliseconds: 50));
      expect(state().preview!.blocks.single.text, 'Jawaban');
      done(time);
      close(time);
    }),
  );

  test(
    'answerNow only applies while reading and resets on the next send',
    () => fakeAsync((time) {
      open(time);
      context.prepareGate = Completer();
      send(time);
      vm().answerNow(); // nothing being read yet
      expect(context.answerNowChecks.last!(), isFalse);
      expect(state().answerRequested, isFalse);
      context.progressSinks.last!((
        completed: 0,
        total: 5,
        label: null,
        notes: const [],
      ));
      pump(time);
      expect(state().canAnswerNow, isTrue);
      vm().answerNow();
      expect(context.answerNowChecks.last!(), isTrue);
      expect(state().answerRequested, isTrue);
      expect(state().canAnswerNow, isFalse);
      context.prepareGate!.complete();
      pump(time);
      done(time);
      context.prepareGate = null;
      send(time, 'Lagi?');
      expect(state().answerRequested, isFalse);
      expect(context.answerNowChecks.last!(), isFalse);
      done(time);
      close(time);
    }),
  );

  test(
    'reading position from launch reaches preparation',
    () => fakeAsync((time) {
      open(time);
      send(time);
      expect(context.readingChapters, [null]);
      done(time);
      unawaited(
        vm().launch(
          ChatLaunchContext(
            book: lifecycleBook,
            returnPosition: (
              chapterId: 7,
              paragraphIndex: 2,
              paragraphOffset: 0,
            ),
          ),
        ),
      );
      pump(time);
      send(time, 'Bab ini bahas apa?');
      expect(context.readingChapters, [null, 7]);
      done(time);
      close(time);
    }),
  );

  test(
    'throttled preview flushes on Stop, revokes sources, and rejects late frames/retry leakage',
    () => fakeAsync((time) {
      open(time);
      send(time);
      final attempt = context.prepared.last;
      attempt.frames.add(
        ChatStreamFrame(
          'raw1',
          preview: [ChatAnswerBlock(text: 'Hai', sources: [])],
        ),
      );
      pump(time);
      expect(state().preview, isNull);
      time.elapse(const Duration(milliseconds: 50));
      expect(state().preview!.blocks.single.text, 'Hai');
      attempt.frames.add(
        ChatStreamFrame(
          'raw12',
          preview: [ChatAnswerBlock(text: 'Hai lagi', sources: [])],
        ),
      );
      pump(time);
      unawaited(vm().stop());
      pump(time);
      expect(state().preview!.blocks.single.text, 'Hai lagi');
      expect(state().preview!.blocks.single.sources, isEmpty);
      expect(state().phase, ChatPhase.stopped);
      time.elapse(const Duration(milliseconds: 100));
      expect(state().preview!.blocks.single.text, 'Hai lagi');
      unawaited(vm().retry());
      pump(time);
      expect(state().preview, isNull);
      close(time);
    }),
  );

  test(
    'restore waits for raw tail flush and blocks new sends, including disposed controllers',
    () => fakeAsync((time) {
      open(time);
      send(time);
      delta(time, '{partial tail');
      final lifecycle = container.read(chatLifecycleProvider);
      repo.finalizeGate = Completer();
      container.invalidate(provider);
      pump(time);
      var closed = false;
      unawaited(lifecycle.close().then((_) => closed = true));
      pump(time);
      expect(closed, false);
      expect(context.cancels.single!.isCancelled, true);
      send(time, 'Blocked');
      expect(repo.creates, 1);
      repo.finalizeGate!.complete();
      pump(time);
      expect(closed, true);
      expect(repo.turns.values.single.phase, ChatPhase.stopped);
      expect(repo.turns.values.single.draft, '{partial tail');
      expect(lifecycle.canStart(1), false);
      close(time);
    }),
  );

  test(
    'content change pauses only its book and awaits stop before mutation',
    () => fakeAsync((time) {
      open(time);
      send(time);
      delta(time, '{tail');
      final lifecycle = container.read(chatLifecycleProvider);
      repo.finalizeGate = Completer();
      var changed = false;
      unawaited(
        lifecycle.changeContent(1, () async {
          changed = true;
        }),
      );
      pump(time);
      expect(changed, false);
      expect(lifecycle.canStart(1), false);
      expect(lifecycle.canStart(2), true);
      repo.finalizeGate!.complete();
      pump(time);
      expect(changed, true);
      expect(lifecycle.canStart(1), true);
      expect(repo.turns.values.single.draft, '{tail');
      close(time);
    }),
  );

  test(
    'failed terminal flush rejects database replacement even after dispose',
    () => fakeAsync((time) {
      open(time);
      send(time);
      delta(time, '{tail');
      repo.finalizeError = StateError('disk full');
      final lifecycle = container.read(chatLifecycleProvider);
      container.invalidate(provider);
      pump(time);
      Object? failure;
      unawaited(
        lifecycle.close().catchError((Object e) {
          failure = e;
        }),
      );
      pump(time);
      expect(failure, isStateError);
      expect(repo.finalized, isEmpty);
      close(time);
    }),
  );

  test(
    'hydrate/list/open and empty submit never create a paid request',
    () => fakeAsync((time) {
      open(time);
      expect(state().loading, false);
      expect(
        state().activeSession,
        isNull,
        reason: "${state().problem}; changing=${state().changingSession}",
      );
      unawaited(vm().send());
      pump(time);
      expect(repo.creates, 0);
      expect(context.calls, 0);
      expect(container.read(chatSessionsProvider(1)).isLoading, true);
      pump(time);
      expect(context.calls, 0);
      close(time);
    }),
  );

  test(
    'first send guards double tap before insert and finishes one turn',
    () => fakeAsync((time) {
      open(time);
      repo.createGate = Completer();
      send(time);
      unawaited(vm().send());
      pump(time);
      expect(repo.creates, 1);
      expect(state().busy, true);
      expect(context.calls, 0);
      repo.createGate!.complete();
      pump(time);
      expect(context.calls, 1);
      expect(state().phase, ChatPhase.waiting);
      done(time);
      expect(state().phase, ChatPhase.done);
      expect(repo.turns.length, 1);
      expect(repo.turns.values.single.phase, ChatPhase.done);
      expect(state().draft, '');
      time.elapse(Duration.zero);
      pump(time);
      expect(time.nonPeriodicTimerCount, 0);
      close(time);
    }),
  );

  test(
    'stop during insert waits for persistence, no orphan running or network',
    () => fakeAsync((time) {
      open(time);
      repo.createGate = Completer();
      send(time);
      var stopped = false;
      unawaited(vm().stop().then((_) => stopped = true));
      pump(time);
      expect(stopped, false);
      repo.createGate!.complete();
      pump(time);
      expect(stopped, true);
      expect(state().activeSession!.id, repo.turns.values.single.sessionId);
      expect(state().draft, isEmpty);
      expect(repo.turns.values.single.phase, ChatPhase.stopped);
      expect(context.calls, 0);
      time.elapse(Duration.zero);
      pump(time);
      expect(time.nonPeriodicTimerCount, 0);
      close(time);
    }),
  );

  test(
    'dispose during model read prevents first insert',
    () => fakeAsync((time) {
      open(time);
      context.modelGate = Completer();
      send(time);
      container.dispose();
      context.modelGate!.complete();
      pump(time);
      expect(repo.creates, 0);
      expect(context.calls, 0);
      time.elapse(Duration.zero);
      pump(time);
      expect(time.nonPeriodicTimerCount, 0);
      context.dispose();
      repo.dispose();
      pump(time);
    }),
  );

  test(
    'dispose during insert flushes late turn via original repo',
    () => fakeAsync((time) {
      open(time);
      repo.createGate = Completer();
      send(time);
      container.dispose();
      repo.createGate!.complete();
      pump(time);
      expect(repo.turns.values.single.phase, ChatPhase.stopped);
      expect(context.calls, 0);
      context.dispose();
      repo.dispose();
      pump(time);
      time.elapse(Duration.zero);
      pump(time);
      expect(time.nonPeriodicTimerCount, 0);
    }),
  );

  test(
    'raw JSON partial checkpoint + stop + retry preserve same user turn',
    () => fakeAsync((time) {
      open(time);
      send(time);
      delta(time, '{"status":"answered",');
      expect(state().phase, ChatPhase.writing);
      unawaited(vm().stop());
      pump(time);
      expect(repo.turns.values.single.draft, '{"status":"answered",');
      expect(repo.turns.values.single.phase, ChatPhase.stopped);
      expect(context.cancels.first!.isCancelled, true);
      expect(state().canRetry, true);
      final old = context.prepared.first;
      unawaited(vm().retry());
      unawaited(vm().retry());
      pump(time);
      expect(repo.retries, 1);
      expect(repo.turns.length, 1);
      expect(repo.turns.values.single.attempt, 2);
      old.frames.add(const ChatStreamFrame('LATE'));
      pump(time);
      expect(repo.turns.values.single.draft, '');
      done(time);
      expect(repo.turns.values.single.phase, ChatPhase.done);
      close(time);
    }),
  );

  test(
    'no key persists failed turn; settings return never auto-retries',
    () => fakeAsync((time) {
      open(time);
      context.error = const AiException(AiError.noApiKey);
      send(time);
      expect(state().phase, ChatPhase.failed);
      expect(state().error!.error, AiError.noApiKey);
      expect(repo.turns.values.single.error, AiError.noApiKey);
      context.error = null;
      time.elapse(const Duration(minutes: 5));
      pump(time);
      expect(context.calls, 1);
      unawaited(vm().retry());
      pump(time);
      expect(context.calls, 2);
      done(time);
      close(time);
    }),
  );

  test(
    'waiting slow15 then timeout30 persists failed with zero automatic retry',
    () => fakeAsync((time) {
      open(time);
      send(time);
      time.elapse(const Duration(seconds: 15));
      pump(time);
      expect(state().phase, ChatPhase.slow);
      time.elapse(const Duration(seconds: 15));
      pump(time);
      expect(state().phase, ChatPhase.failed);
      expect(state().error!.error, AiError.timeout);
      expect(repo.turns.values.single.phase, ChatPhase.failed);
      expect(context.calls, 1);
      close(time);
    }),
  );

  test(
    'first raw token clears waiting deadline; 20s stall flushes cut',
    () => fakeAsync((time) {
      open(time);
      send(time);
      time.elapse(const Duration(seconds: 14));
      delta(time, '{');
      time.elapse(const Duration(seconds: 19));
      pump(time);
      expect(state().phase, ChatPhase.writing);
      time.elapse(const Duration(seconds: 1));
      pump(time);
      expect(state().phase, ChatPhase.cut);
      expect(repo.turns.values.single.draft, '{');
      expect(repo.turns.values.single.error, AiError.timeout);
      close(time);
    }),
  );

  test(
    'retrieval has bounded deadline and late prepared result is ignored',
    () => fakeAsync((time) {
      open(time);
      context.prepareGate = Completer();
      send(time);
      time.elapse(const Duration(seconds: 15));
      pump(time);
      expect(state().phase, ChatPhase.slow);
      time.elapse(ChatViewModel.retrievalTimeout - const Duration(seconds: 15));
      pump(time);
      expect(state().phase, ChatPhase.failed);
      expect(repo.turns.values.single.error, AiError.timeout);
      context.prepareGate!.complete();
      pump(time);
      expect(context.prepared, isEmpty);
      close(time);
    }),
  );

  test(
    'network after partial is cut; invalid response is preserved and not retried',
    () => fakeAsync((time) {
      open(time);
      send(time);
      delta(time, '{"claims":[');
      context.prepared.last.frames.addError(
        const AiException(AiError.invalidResponse),
      );
      pump(time);
      expect(state().phase, ChatPhase.cut);
      expect(state().error!.error, AiError.invalidResponse);
      expect(repo.turns.values.single.error, AiError.invalidResponse);
      expect(context.calls, 1);
      close(time);
    }),
  );

  test(
    'switch/new flush first, restore anchor, and never auto-send',
    () => fakeAsync((time) {
      open(time);
      send(time);
      final first = state().activeSession!.id;
      delta(time, '{');
      const anchor = (turnId: 1, blockIndex: 0, alignment: .5);
      vm().setScrollAnchor(anchor);
      unawaited(vm().newSession());
      pump(time);
      expect(repo.turns[1]!.phase, ChatPhase.stopped);
      expect(
        state().activeSession,
        isNull,
        reason: "${state().problem}; changing=${state().changingSession}",
      );
      expect(repo.sessions[first]!.scrollAnchor, anchor);
      expect(repo.sessions.length, 1);
      send(time, 'New?');
      done(time);
      unawaited(vm().openSession(first));
      pump(time);
      expect(state().activeSession!.id, first);
      expect(state().scrollAnchor, anchor);
      expect(context.calls, 2);
      expect(repo.opened, 1);
      close(time);
    }),
  );

  test(
    'delete active during stream cancels and falls back without ghost sessions',
    () => fakeAsync((time) {
      open(time);
      send(time);
      final old = context.prepared.single;
      unawaited(vm().deleteSession(state().activeSession!.id));
      pump(time);
      expect(repo.sessions, isEmpty);
      expect(repo.turns, isEmpty);
      expect(
        state().activeSession,
        isNull,
        reason: "${state().problem}; changing=${state().changingSession}",
      );
      old.frames.add(const ChatStreamFrame('LATE'));
      pump(time);
      expect(repo.turns, isEmpty);
      expect(context.calls, 1);
      close(time);
    }),
  );

  test(
    'revision change cancels request and exposes old session read-only',
    () => fakeAsync((time) {
      open(time);
      send(time);
      repo.revision((bookId: 1, contentRevision: 2));
      pump(time);
      expect(context.cancels.single!.isCancelled, true);
      expect(state().archived, true);
      expect(state().canSend, false);
      expect(state().canRetry, false);
      unawaited(vm().newSession());
      pump(time);
      expect(
        state().readOnly,
        false,
        reason: "${state().problem}; changing=${state().changingSession}",
      );
      expect(context.calls, 1);
      close(time);
    }),
  );

  test(
    'book deleted and session deleted externally have safe recovery states',
    () => fakeAsync((time) {
      open(time);
      send(time);
      repo.revision(null);
      pump(time);
      expect(state().readOnly, true);
      expect(state().problem, contains('dihapus'));
      expect(context.cancels.single!.isCancelled, true);
      close(time);
    }),
  );

  test(
    'quote launch during hydrate waits, remains draft, and can be removed',
    () => fakeAsync((time) {
      repo = LifecycleRepo();
      context = LifecycleContext(repo);
      container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatContextRepositoryProvider.overrideWithValue(context),
        ],
      );
      container.listen(provider, (_, _) {});
      final quote = ChatQuote(
        anchors: [
          SourceAnchor(
            book: lifecycleBook,
            chapterId: 1,
            paragraphIndex: 0,
            start: 0,
            end: 1,
            paragraphHash: chatTextHash('A'),
            snapshot: 'A',
          ),
        ],
      );
      unawaited(
        vm().launch(
          ChatLaunchContext(
            book: lifecycleBook,
            quote: quote,
            returnPosition: (
              chapterId: 1,
              paragraphIndex: 0,
              paragraphOffset: 0,
            ),
          ),
        ),
      );
      pump(time);
      expect(state().selectedQuote, quote);
      expect(repo.sessions, isEmpty);
      vm().removeQuote();
      expect(state().selectedQuote, isNull);
      expect(context.calls, 0);
      close(time);
    }),
  );

  test(
    'provider rebuild captures original repo for pending flush, new DB stays untouched',
    () => fakeAsync((time) {
      open(time);
      repo.createGate = Completer();
      send(time);
      final oldRepo = repo, oldContext = context;
      final nextRepo = LifecycleRepo();
      final nextContext = LifecycleContext(nextRepo);
      container.updateOverrides([
        chatRepositoryProvider.overrideWithValue(nextRepo),
        chatContextRepositoryProvider.overrideWithValue(nextContext),
      ]);
      pump(time);
      oldRepo.createGate!.complete();
      pump(time);
      expect(oldRepo.turns.values.single.phase, ChatPhase.stopped);
      expect(nextRepo.turns, isEmpty);
      expect(nextContext.calls, 0);
      container.dispose();
      pump(time);
      oldContext.dispose();
      oldRepo.dispose();
      nextContext.dispose();
      nextRepo.dispose();
      pump(time);
      time.elapse(Duration.zero);
      pump(time);
      expect(time.nonPeriodicTimerCount, 0);
    }),
  );
  test(
    'insert error terminates without deadlocking and preserves unsent draft',
    () => fakeAsync((time) {
      open(time);
      repo.createError = StateError('storage failed');
      send(time, 'Keep this question');
      expect(state().phase, ChatPhase.failed);
      expect(state().draft, 'Keep this question');
      expect(state().busy, false);
      expect(repo.sessions, isEmpty);
      expect(context.calls, 0);
      close(time);
    }),
  );

  test(
    'switch waits for terminal write and blocks another send until flush',
    () => fakeAsync((time) {
      open(time);
      send(time);
      delta(time, '{partial');
      final original = state().activeSession!.id;
      repo.finalizeGate = Completer();
      var changed = false;
      unawaited(vm().newSession().then((_) => changed = true));
      pump(time);
      expect(changed, false);
      expect(state().activeSession!.id, original);
      expect(context.cancels.single!.isCancelled, true);
      vm().setDraft('duplicate');
      unawaited(vm().send());
      pump(time);
      expect(context.calls, 1);
      repo.finalizeGate!.complete();
      pump(time);
      expect(changed, true);
      expect(state().activeSession, isNull);
      expect(repo.turns.values.single.phase, ChatPhase.stopped);
      expect(repo.turns.values.single.draft, '{partial');
      close(time);
    }),
  );

  test(
    'dispose while writing flushes latest raw draft and drops late output',
    () => fakeAsync((time) {
      open(time);
      send(time);
      delta(time, '{partial');
      final old = context.prepared.single;
      container.dispose();
      pump(time);
      expect(repo.turns.values.single.phase, ChatPhase.stopped);
      expect(repo.turns.values.single.draft, '{partial');
      old.frames.add(const ChatStreamFrame('LATE'));
      pump(time);
      expect(repo.finalized, hasLength(1));
      context.dispose();
      repo.dispose();
      pump(time);
      expect(time.nonPeriodicTimerCount, 0);
    }),
  );

  test(
    'HTTP before content persists failed status without retry',
    () => fakeAsync((time) {
      open(time);
      context.error = const AiException(AiError.http, status: 429);
      send(time);
      expect(state().phase, ChatPhase.failed);
      expect(state().error!.status, 429);
      expect(repo.turns.values.single.httpStatus, 429);
      expect(context.calls, 1);
      close(time);
    }),
  );

  test(
    'over-budget Unicode question is rejected before storage/model/network',
    () => fakeAsync((time) {
      open(time);
      send(time, '🌿' * 501);
      expect(repo.creates, 0);
      expect(context.models, 0);
      expect(context.calls, 0);
      expect(state().problem, contains('panjang'));
      expect(state().draft, isNotEmpty);
      close(time);
    }),
  );
  test(
    'app background cancels and flushes; resume never auto-sends',
    () => fakeAsync((time) {
      open(time);
      send(time);
      delta(time, '{partial');
      final binding = WidgetsBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pump(time);
      expect(repo.turns.values.single.phase, ChatPhase.stopped);
      expect(repo.turns.values.single.draft, '{partial');
      expect(context.cancels.single!.isCancelled, true);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      pump(time);
      expect(context.calls, 1);
      close(time);
    }),
  );
}
