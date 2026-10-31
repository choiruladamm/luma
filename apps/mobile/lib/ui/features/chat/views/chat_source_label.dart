import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/chat_repository.dart';
import '../../../../domain/models/book_chat.dart';

final chatChapterNumbersProvider = FutureProvider.autoDispose
    .family<Map<int, int>, int>(
      (ref, bookId) => ref.watch(chatRepositoryProvider).chapterNumbers(bookId),
    );

/// "2.4" = bab 2, bagian 4. Nomor bab belum kebaca: pakai judul bab.
String chatSourceLabel(ChatSource source, Map<int, int>? chapters) {
  final first = source.anchors.first;
  final chapter = chapters?[first.chapterId];
  if (chapter == null) return source.chapterTitle;
  return '$chapter.${first.paragraphIndex + 1}';
}
