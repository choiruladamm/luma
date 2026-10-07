import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/ai_results_repository.dart';
import '../../../../data/repositories/book_repository.dart';
import '../../../../data/repositories/reading_progress_repository.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/openrouter_service.dart';
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
