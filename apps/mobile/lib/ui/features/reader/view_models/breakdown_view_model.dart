import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/ai_breakdowns_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/openrouter_service.dart';
import '../../../../domain/breakdown_prompt.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/breakdown.dart';
import 'reader_view_model.dart';

/// Bedahin satu grup yang lagi di-stream / dari cache.
class BreakdownState {
  const BreakdownState({
    this.phase = BreakdownPhase.waiting,
    this.input,
    this.draft = const Breakdown(),
    this.error,
    this.cached = false,
  });

  final BreakdownPhase phase;

  /// Terjemahan yang dibedah (panel teks). Null = belum kebaca dari DB.
  final BreakdownInput? input;

  /// [BreakdownPhase.done]: isinya hasil akhir yang valid.
  final Breakdown draft;

  /// [BreakdownPhase.failed].
  final AiException? error;

  /// Langsung dari cache, gak ada yang di-stream.
  final bool cached;

  BreakdownState withPhase(BreakdownPhase phase) => BreakdownState(
    phase: phase,
    input: input,
    draft: draft,
    error: error,
    cached: cached,
  );
}

/// Sumber layar Bedahin (docs/architecture.md). Cache `ai_breakdowns` dulu
/// (versi prompt + terjemahan sama); kalau belum ada, di-stream dengan
/// ambang yang sama kayak [GroupAiStream]. Jawaban lengkap divalidasi; gak
/// valid → di-stream sekali lagi, masih gagal → `invalidResponse`. Cuma yang
/// valid yang disimpen. Ke-dispose = request dibatalin, gak ada yang
/// disimpen. Coba lagi = `ref.invalidate`.
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
    // Ambil semua sebelum await.
    final repo = ref.read(aiBreakdownsRepositoryProvider);
    final ai = ref.read(openRouterServiceProvider);
    final keys = ref.read(apiKeyStoreProvider);
    final settings = ref.read(settingsRepositoryProvider);

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
        // Bedahin cuma kebuka abis makna cepat selesai.
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
        )) {
          // Token telat abis layar ditutup: jangan pasang timer yang baca
          // `state`.
          if (!run.live) return;
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
          run.stall = Timer(
            GroupAiStream.stallAfter,
            () => finish(state.withPhase(BreakdownPhase.cut)),
          );
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
      // Layar ditutup: request yang dibatalin ngelempar error, dan `state`
      // udah gak boleh dibaca.
      if (!run.live) return;
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

/// Jumlah bagian bedahan grup ini yang masih berlaku (0 = belum ada): > 0,
/// entri di sheet Artinya jadi "Buka bedahan · N bagian".
final breakdownSectionsProvider = FutureProvider.autoDispose
    .family<int, GroupRef>(
      (ref, group) => ref.watch(aiBreakdownsRepositoryProvider).sections(group),
    );

/// Kartu Nyambung ke: dari grup mana, ke bab ke berapa (null = lanjutan).
typedef PeekKey = ({GroupRef from, int? chapter});

/// Isi sheet intip (#65). Null = tujuannya gak ada, kartu jadi teks biasa.
final breakdownPeekProvider = FutureProvider.autoDispose
    .family<BreakdownPeek?, PeekKey>(
      (ref, key) =>
          ref.watch(aiBreakdownsRepositoryProvider).peek(key.from, key.chapter),
    );
