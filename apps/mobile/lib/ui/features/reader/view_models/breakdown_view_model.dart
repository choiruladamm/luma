import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/ai_breakdowns_repository.dart';
import '../../../../data/repositories/ai_calls_repository.dart';
import '../../../../data/repositories/ai_key_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/openrouter_service.dart';
import '../../../../domain/ai_call_meter.dart';
import '../../../../domain/breakdown_prompt.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/breakdown.dart';
import 'reader_view_model.dart';

/// Bedahin of one group, streaming or from the cache.
class BreakdownState {
  const BreakdownState({
    this.phase = BreakdownPhase.waiting,
    this.input,
    this.draft = const Breakdown(),
    this.error,
    this.cached = false,
  });

  final BreakdownPhase phase;

  /// The translation being broken down (text panel). Null = not yet read from the DB.
  final BreakdownInput? input;

  /// [BreakdownPhase.done]: holds the final valid result.
  final Breakdown draft;

  /// [BreakdownPhase.failed].
  final AiException? error;

  /// Straight from the cache, nothing streamed.
  final bool cached;

  BreakdownState withPhase(BreakdownPhase phase) => BreakdownState(
    phase: phase,
    input: input,
    draft: draft,
    error: error,
    cached: cached,
  );
}

/// Source of the Bedahin screen (docs/architecture.md). Checks the `ai_breakdowns`
/// cache first (same prompt version + translation); if absent, streams with the
/// same thresholds as [GroupAiStream]. A complete answer is validated; if invalid
/// it streams once more, and if that also fails: `invalidResponse`. Only valid
/// answers are saved. Disposal cancels the request and saves nothing. Retry =
/// `ref.invalidate`.
class BreakdownStream extends Notifier<BreakdownState> {
  BreakdownStream(this.group);

  final GroupRef group;

  @override
  BreakdownState build() {
    final run = AiRun();
    ref.onDispose(run.stop);
    unawaited(_run(run));
    return const BreakdownState();
  }

  Future<void> _run(AiRun run) async {
    // Read everything before the await.
    final repo = ref.read(aiBreakdownsRepositoryProvider);
    final ai = ref.read(openRouterServiceProvider);
    final keys = ref.read(aiKeyRepositoryProvider);
    final settings = ref.read(settingsRepositoryProvider);
    final calls = ref.read(aiCallsRepositoryProvider);
    void Function([AiError? error])? log;

    void emit(BreakdownState next) {
      if (run.live) state = next;
    }

    void finish(BreakdownState next) {
      emit(next);
      run.stop();
    }

    BreakdownInput? input;
    var streaming = false;
    try {
      input = await repo.input(group);
      if (input == null) {
        // Bedahin only opens after the quick meaning has finished.
        throw const AiException(
          AiError.invalidResponse,
          detail: 'no quick meaning',
        );
      }
      final hash = breakdownSourceHash(input.translations);
      final cached = await repo.find(group, hash);
      if (cached != null) {
        return finish(
          BreakdownState(
            phase: BreakdownPhase.done,
            input: input,
            draft: parseBreakdown(cached, input),
            cached: true,
          ),
        );
      }
      emit(BreakdownState(input: input));
      final model = await settings.watchModel().first;
      final apiKey = await keys.read();
      if (!run.live) return;
      final meter = AiCallMeter();
      final chars = input.original.fold(0, (sum, p) => sum + p.length);
      var logged = false;
      // Logging must never break the answer, so its errors are dropped.
      log = ([error]) {
        if (logged) return;
        logged = true;
        calls
            .record(
              kind: AiCallKind.breakdown,
              model: model,
              promptVersion: breakdownPromptVersion,
              chars: chars,
              apiKey: apiKey,
              totalMs: meter.totalMs,
              firstTokenMs: meter.firstTokenMs,
              usage: meter.usage,
              group: group,
              error: error,
            )
            .ignore();
      };

      for (var attempt = 1; ; attempt++) {
        run.timers
          ..add(
            Timer(
              GroupAiStream.slowAfter,
              () => emit(state.withPhase(BreakdownPhase.slow)),
            ),
          )
          ..add(
            Timer(GroupAiStream.timeoutAfter, () {
              log?.call(AiError.timeout);
              finish(
                BreakdownState(
                  phase: BreakdownPhase.failed,
                  input: input,
                  error: const AiException(AiError.timeout),
                ),
              );
            }),
          );

        var content = '';
        streaming = true;
        await for (final delta in ai.breakdownStream(
          apiKey: apiKey,
          model: model,
          input: input,
          cancel: run.cancel,
          onUsage: meter.add,
        )) {
          // A token arriving after the screen closed: don't set a timer that reads
          // `state`.
          if (!run.live) return;
          meter.firstToken();
          if (content.isEmpty) run.clearTimers();
          content += delta;
          emit(
            BreakdownState(
              phase: BreakdownPhase.writing,
              input: input,
              draft: parseBreakdownDraft(content),
            ),
          );
          run.stall?.cancel();
          run.stall = Timer(GroupAiStream.stallAfter, () {
            log?.call(AiError.timeout);
            finish(state.withPhase(BreakdownPhase.cut));
          });
        }
        streaming = false;
        run.stall?.cancel();
        run.clearTimers();
        if (!run.live) return;

        final Breakdown result;
        try {
          result = parseBreakdown(content, input);
        } on AiException {
          if (attempt >= 2) rethrow;
          emit(BreakdownState(input: input));
          continue;
        }
        log();
        await repo.save(group, body: content, sourceHash: hash, model: model);
        if (!run.live) return;
        ref.invalidate(breakdownSectionsProvider(group));
        return finish(
          BreakdownState(
            phase: BreakdownPhase.done,
            input: input,
            draft: result,
          ),
        );
      }
    } on AiException catch (e) {
      // The screen closed: a cancelled request throws, and `state` must not be
      // read.
      if (!run.live) return;
      log?.call(e.error);
      if (streaming && state.phase == BreakdownPhase.writing) {
        finish(state.withPhase(BreakdownPhase.cut));
      } else {
        finish(
          BreakdownState(phase: BreakdownPhase.failed, input: input, error: e),
        );
      }
    }
  }
}

final breakdownStreamProvider = NotifierProvider.autoDispose
    .family<BreakdownStream, BreakdownState, GroupRef>(BreakdownStream.new);

/// Number of this group's breakdown parts that are still valid (0 = none yet): when
/// > 0, the Artinya sheet entry reads "Buka bedahan · N bagian".
final breakdownSectionsProvider = FutureProvider.autoDispose
    .family<int, GroupRef>(
      (ref, group) => ref.watch(aiBreakdownsRepositoryProvider).sections(group),
    );

/// The Nyambung ke card: from which group, to which chapter (null = a continuation).
typedef PeekKey = ({GroupRef from, int? chapter});

/// Content of the peek sheet. Null = the target does not exist, the card becomes plain text.
final breakdownPeekProvider = FutureProvider.autoDispose
    .family<BreakdownPeek?, PeekKey>(
      (ref, key) =>
          ref.watch(aiBreakdownsRepositoryProvider).peek(key.from, key.chapter),
    );
