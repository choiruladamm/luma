import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/ai_calls_repository.dart';
import '../../../../data/repositories/ai_key_repository.dart';
import '../../../../data/repositories/ai_results_repository.dart';
import '../../../../data/repositories/book_repository.dart';
import '../../../../data/repositories/reading_progress_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/openrouter_service.dart';
import '../../../../domain/ai_call_meter.dart';
import '../../../../domain/ai_prompt.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/book.dart';

/// Injectable wall clock for reader activity accounting.
final readerNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The book + chapter list. The table of contents uses it too.
final readerBookProvider = FutureProvider.autoDispose.family<ReaderBook?, int>(
  (ref, bookId) => ref.watch(bookRepositoryProvider).readerBook(bookId),
);

final chapterParagraphsProvider = FutureProvider.autoDispose
    .family<List<ReaderParagraph>, int>(
      (ref, chapterId) =>
          ref.watch(bookRepositoryProvider).paragraphs(chapterId),
    );

/// The last saved position; the book opens there.
final readingPositionProvider = FutureProvider.autoDispose
    .family<ReadingPosition?, int>(
      (ref, bookId) =>
          ref.watch(readingProgressRepositoryProvider).load(bookId),
    );

/// Number of paragraphs already explained in one chapter (chapter-end card).
final chapterTranslatedProvider = FutureProvider.autoDispose.family<int, int>(
  (ref, chapterId) =>
      ref.watch(bookRepositoryProvider).translatedInChapter(chapterId),
);

/// Translation + meaning of one group (docs/architecture.md): the `ai_results` cache
/// first, and only if absent calls the LLM and saves the result. The same group is
/// never sent to the LLM twice. A failure (no key, timeout, etc.) becomes an
/// `AsyncError` holding an `AiException`; it is not retried automatically (each
/// try costs balance), retry via `ref.invalidate`.
final groupAiProvider = FutureProvider.autoDispose.family<AiReply, GroupRef>((
  ref,
  group,
) async {
  // Read everything before the await: the provider may be disposed while waiting
  // for the LLM, and the result is still saved.
  final cache = ref.watch(aiResultsRepositoryProvider);
  final ai = ref.watch(openRouterServiceProvider);
  final keys = ref.watch(aiKeyRepositoryProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  final calls = ref.watch(aiCallsRepositoryProvider);

  final cached = await cache.find(group);
  if (cached != null) {
    cache.markOpened(group).ignore();
    return cached;
  }
  final text = await cache.promptText(group);
  final model = await settings.watchModel().first;
  final apiKey = await keys.read();
  final meter = AiCallMeter();
  void log([AiError? error]) =>
      _logGroup(calls, group, text.target, model, apiKey, meter, error);
  final AiReply reply;
  try {
    reply = await ai.explain(
      apiKey: apiKey,
      model: model,
      book: text.book,
      context: text.context,
      target: text.target,
      onUsage: meter.add,
    );
  } on AiException catch (e) {
    log(e.error);
    rethrow;
  }
  log();
  await cache.save(group, reply, model: model);
  return reply;
}, retry: (_, _) => null);

/// Logging must never break the answer, so its errors are dropped.
void _logGroup(
  AiCallsRepository calls,
  GroupRef group,
  List<String> target,
  String model,
  String? apiKey,
  AiCallMeter meter,
  AiError? error,
) => calls
    .record(
      kind: AiCallKind.group,
      model: model,
      promptVersion: aiPromptVersion,
      chars: target.fold(0, (sum, p) => sum + p.length),
      apiKey: apiKey,
      totalMs: meter.totalMs,
      firstTokenMs: meter.firstTokenMs,
      usage: meter.usage,
      group: group,
      error: error,
    )
    .ignore();

/// The answer of one group being streamed: [draft] = what has arrived from the
/// network (not yet paced; the UI sets the rhythm).
class AiStream {
  const AiStream({
    this.phase = AiPhase.waiting,
    this.draft = const AiDraft(),
    this.sources = const [],
    this.error,
    this.cached = false,
  });

  final AiPhase phase;

  /// [AiPhase.done]: holds the final answer.
  final AiDraft draft;

  /// Length of each original paragraph, to estimate the placeholder height.
  final List<int> sources;

  /// [AiPhase.failed].
  final AiException? error;

  /// Straight from the cache, nothing streamed.
  final bool cached;

  AiStream withPhase(AiPhase phase) => AiStream(
    phase: phase,
    draft: draft,
    sources: sources,
    error: error,
    cached: cached,
  );
}

/// Source of the Artinya sheet: the streaming version of [groupAiProvider]
/// (docs/architecture.md, docs/llm.md).
/// Cache first; if absent, the sectioned answer is streamed with [AiPhase] states.
/// Timeouts: 15 seconds without a token = [AiPhase.slow] (the request keeps
/// running), 30 seconds = `timeout` failure; tokens stopping for 20 seconds
/// mid-way = [AiPhase.cut]. A complete answer is validated; if invalid, tried once
/// more over the non-streaming JSON path. Only complete, valid answers are saved.
/// Disposal (sheet closed, Lanjut) cancels the request and saves nothing. Retry =
/// `ref.invalidate`, starting over.
class GroupAiStream extends Notifier<AiStream> {
  GroupAiStream(this.group);

  final GroupRef group;

  static const slowAfter = Duration(seconds: 15);
  static const timeoutAfter = Duration(seconds: 30);
  static const stallAfter = Duration(seconds: 20);

  @override
  AiStream build() {
    final run = AiRun();
    ref.onDispose(run.stop);
    unawaited(_run(run));
    return const AiStream();
  }

  Future<void> _run(AiRun run) async {
    // Read everything before the await.
    final cache = ref.read(aiResultsRepositoryProvider);
    final ai = ref.read(openRouterServiceProvider);
    final keys = ref.read(aiKeyRepositoryProvider);
    final settings = ref.read(settingsRepositoryProvider);
    final calls = ref.read(aiCallsRepositoryProvider);
    void Function([AiError? error])? log;

    void emit(AiStream next) {
      if (run.live) state = next;
    }

    void finish(AiStream next) {
      emit(next);
      run.stop();
    }

    var sources = const <int>[];
    var streaming = false;
    try {
      final cached = await cache.find(group);
      if (cached != null) {
        cache.markOpened(group).ignore();
        return finish(
          AiStream(phase: AiPhase.done, draft: _draft(cached), cached: true),
        );
      }
      final text = await cache.promptText(group);
      sources = [for (final p in text.target) p.length];
      emit(AiStream(sources: sources));
      final model = await settings.watchModel().first;
      final apiKey = await keys.read();
      if (!run.live) return;
      final meter = AiCallMeter();
      var logged = false;
      log = ([error]) {
        if (logged) return;
        logged = true;
        _logGroup(calls, group, text.target, model, apiKey, meter, error);
      };

      run.timers
        ..add(Timer(slowAfter, () => emit(state.withPhase(AiPhase.slow))))
        ..add(
          Timer(timeoutAfter, () {
            log?.call(AiError.timeout);
            finish(
              AiStream(
                phase: AiPhase.failed,
                sources: sources,
                error: const AiException(AiError.timeout),
              ),
            );
          }),
        );

      var content = '';
      streaming = true;
      await for (final delta in ai.explainStream(
        apiKey: apiKey,
        model: model,
        book: text.book,
        context: text.context,
        target: text.target,
        cancel: run.cancel,
        onUsage: meter.add,
      )) {
        // A token arriving after the screen closed: don't set a timer that reads
        // `state`.
        if (!run.live) return;
        meter.firstToken();
        if (content.isEmpty) run.clearTimers();
        content += delta;
        final draft = parseAiDraft(content);
        emit(
          AiStream(
            phase: draft.meaning == null
                ? AiPhase.translating
                : AiPhase.meaning,
            draft: draft,
            sources: sources,
          ),
        );
        run.stall?.cancel();
        run.stall = Timer(stallAfter, () {
          log?.call(AiError.timeout);
          finish(state.withPhase(AiPhase.cut));
        });
      }
      streaming = false;
      run.stall?.cancel();
      if (!run.live) return;

      AiReply reply;
      try {
        reply = parseAiSections(content, text.target.length);
      } on AiException {
        reply = await ai.explain(
          apiKey: apiKey,
          model: model,
          book: text.book,
          context: text.context,
          target: text.target,
          attempts: 1,
          onUsage: meter.add,
        );
      }
      if (!run.live) return;
      log();
      await cache.save(group, reply, model: model);
      finish(
        AiStream(phase: AiPhase.done, draft: _draft(reply), sources: sources),
      );
    } on AiException catch (e) {
      // The sheet closed: a cancelled request throws, and `state` must not be
      // read.
      if (!run.live) return;
      log?.call(e.error);
      if (streaming &&
          state.phase != AiPhase.waiting &&
          state.phase != AiPhase.slow) {
        finish(state.withPhase(AiPhase.cut));
      } else {
        finish(AiStream(phase: AiPhase.failed, sources: sources, error: e));
      }
    }
  }

  static AiDraft _draft(AiReply r) =>
      AiDraft(translations: r.translations, meaning: r.meaning);
}

/// One request attempt; dies when the provider is disposed / invalidated or once
/// the final result exists. Results arriving after that are dropped.
class AiRun {
  bool live = true;
  final cancel = CancelToken();
  final timers = <Timer>[];
  Timer? stall;

  void clearTimers() {
    for (final t in timers) {
      t.cancel();
    }
  }

  void stop() {
    live = false;
    clearTimers();
    stall?.cancel();
    cancel.cancel();
  }
}

final groupAiStreamProvider = NotifierProvider.autoDispose
    .family<GroupAiStream, AiStream, GroupRef>(GroupAiStream.new);

/// Groups already translated in one chapter: a `mark` line in the margin; tapping
/// the group fills the sheet right away.
final translatedGroupsProvider = StreamProvider.autoDispose
    .family<Set<int>, int>(
      (ref, chapterId) =>
          ref.watch(aiResultsRepositoryProvider).watchGroups(chapterId),
    );

/// Summary of the end-of-book screen.
final bookEndProvider = FutureProvider.autoDispose.family<BookEnd?, int>(
  (ref, bookId) => ref.watch(bookRepositoryProvider).bookEnd(bookId),
);
