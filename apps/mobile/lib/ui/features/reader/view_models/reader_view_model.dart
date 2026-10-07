import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/ai_results_repository.dart';
import '../../../../data/repositories/book_repository.dart';
import '../../../../data/repositories/reading_progress_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/openrouter_service.dart';
import '../../../../domain/ai_prompt.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/book.dart';

/// Buku + daftar chapter. Daftar isi (#17) pake ini juga.
final readerBookProvider = FutureProvider.autoDispose.family<ReaderBook?, int>(
  (ref, bookId) => ref.watch(bookRepositoryProvider).readerBook(bookId),
);

final chapterParagraphsProvider = FutureProvider.autoDispose
    .family<List<ReaderParagraph>, int>(
      (ref, chapterId) =>
          ref.watch(bookRepositoryProvider).paragraphs(chapterId),
    );

/// Posisi terakhir yang disimpen, buat buka buku di tempat terakhir.
final readingPositionProvider = FutureProvider.autoDispose
    .family<ReadingPosition?, int>(
      (ref, bookId) =>
          ref.watch(readingProgressRepositoryProvider).load(bookId),
    );

/// Jumlah paragraf yang udah diartiin di satu chapter (kartu akhir bab).
final chapterTranslatedProvider = FutureProvider.autoDispose.family<int, int>(
  (ref, chapterId) =>
      ref.watch(bookRepositoryProvider).translatedInChapter(chapterId),
);

/// Terjemahan + makna satu grup (docs bagian 8): cache `ai_results` dulu,
/// kalau belum ada baru manggil LLM terus disimpen. Grup yang sama gak
/// pernah manggil LLM dua kali. Gagal (gak ada key, timeout, dll) jadi
/// `AsyncError` berisi `AiException`; gak di-retry otomatis (tiap coba =
/// saldo), ulang lewat `ref.invalidate`.
final groupAiProvider = FutureProvider.autoDispose.family<AiReply, GroupRef>((
  ref,
  group,
) async {
  // Ambil semua sebelum await: provider bisa ke-dispose pas nunggu LLM,
  // hasilnya tetep disimpen.
  final cache = ref.watch(aiResultsRepositoryProvider);
  final ai = ref.watch(openRouterServiceProvider);
  final keys = ref.watch(apiKeyStoreProvider);
  final settings = ref.watch(settingsRepositoryProvider);

  final cached = await cache.find(group);
  if (cached != null) return cached;
  final text = await cache.promptText(group);
  final model = await settings.watchModel().first;
  final reply = await ai.explain(
    apiKey: await keys.read(),
    model: model,
    context: text.context,
    target: text.target,
  );
  await cache.save(group, reply, model: model);
  return reply;
}, retry: (_, _) => null);

/// Jawaban satu grup yang lagi di-stream: [draft] = yang udah dateng dari
/// jaringan (belum di-pacing, UI yang ngatur ritmenya).
class AiStream {
  const AiStream({
    this.phase = AiPhase.waiting,
    this.draft = const AiDraft(),
    this.sources = const [],
    this.error,
    this.cached = false,
  });

  final AiPhase phase;

  /// [AiPhase.done]: isinya jawaban akhir.
  final AiDraft draft;

  /// Panjang tiap paragraf asli, buat ngira tinggi placeholder.
  final List<int> sources;

  /// [AiPhase.failed].
  final AiException? error;

  /// Langsung dari cache, gak ada yang di-stream.
  final bool cached;

  AiStream withPhase(AiPhase phase) => AiStream(
    phase: phase,
    draft: draft,
    sources: sources,
    error: error,
    cached: cached,
  );
}

/// Sumber sheet Artinya: [groupAiProvider] versi streaming (docs bagian 8–9).
/// Cache dulu; kalau belum ada, jawaban bersection di-stream dengan state
/// [AiPhase]. Timeout: 15 detik tanpa token = [AiPhase.slow] (request tetep
/// jalan), 30 detik = gagal `timeout`; token berhenti 20 detik di tengah =
/// [AiPhase.cut]. Jawaban lengkap divalidasi; gak valid → sekali lagi lewat
/// jalur JSON tanpa streaming. Cuma yang lengkap dan valid yang disimpen.
/// Ke-dispose (tutup sheet, Lanjut) = request dibatalin, gak ada yang
/// disimpen. Coba lagi = `ref.invalidate`, mulai dari awal.
class GroupAiStream extends Notifier<AiStream> {
  GroupAiStream(this.group);

  final GroupRef group;

  static const slowAfter = Duration(seconds: 15);
  static const timeoutAfter = Duration(seconds: 30);
  static const stallAfter = Duration(seconds: 20);

  @override
  AiStream build() {
    final run = _Run();
    ref.onDispose(run.stop);
    unawaited(_run(run));
    return const AiStream();
  }

  Future<void> _run(_Run run) async {
    // Ambil semua sebelum await.
    final cache = ref.read(aiResultsRepositoryProvider);
    final ai = ref.read(openRouterServiceProvider);
    final keys = ref.read(apiKeyStoreProvider);
    final settings = ref.read(settingsRepositoryProvider);

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

      run.timers
        ..add(Timer(slowAfter, () => emit(state.withPhase(AiPhase.slow))))
        ..add(
          Timer(timeoutAfter, () {
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
        context: text.context,
        target: text.target,
        cancel: run.cancel,
      )) {
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
        run.stall = Timer(
          stallAfter,
          () => finish(state.withPhase(AiPhase.cut)),
        );
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
          context: text.context,
          target: text.target,
          attempts: 1,
        );
      }
      if (!run.live) return;
      await cache.save(group, reply, model: model);
      finish(
        AiStream(phase: AiPhase.done, draft: _draft(reply), sources: sources),
      );
    } on AiException catch (e) {
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

/// Satu percobaan request; mati pas provider ke-dispose / di-invalidate atau
/// pas udah ada hasil akhir. Hasil yang dateng setelah itu dibuang.
class _Run {
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

/// Grup yang udah diterjemahin di satu chapter: garis `mark` di margin, tap
/// grup itu sheet-nya langsung keisi.
final translatedGroupsProvider = StreamProvider.autoDispose
    .family<Set<int>, int>(
      (ref, chapterId) =>
          ref.watch(aiResultsRepositoryProvider).watchGroups(chapterId),
    );

/// Rekap layar akhir buku.
final bookEndProvider = FutureProvider.autoDispose.family<BookEnd?, int>(
  (ref, bookId) => ref.watch(bookRepositoryProvider).bookEnd(bookId),
);
