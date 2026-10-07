import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/book_repository.dart';
import '../../../../data/repositories/reading_progress_repository.dart';
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

/// Rekap layar akhir buku.
final bookEndProvider = FutureProvider.autoDispose.family<BookEnd?, int>(
  (ref, bookId) => ref.watch(bookRepositoryProvider).bookEnd(bookId),
);
