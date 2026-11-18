import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/chat_repository.dart';
import '../../../../domain/models/book_chat.dart';

final chatChapterNumbersProvider = FutureProvider.autoDispose
    .family<Map<int, int>, int>(
      (ref, bookId) => ref.watch(chatRepositoryProvider).chapterNumbers(bookId),
    );

/// Returns the source label, e.g. "2.4" for chapter 2, paragraph 4.
///
/// Falls back to the chapter title while chapter numbers haven't loaded.
String chatSourceLabel(ChatSource source, Map<int, int>? chapters) {
  final first = source.anchors.first;
  final chapter = chapters?[first.chapterId];
  if (chapter == null) return source.chapterTitle;
  return '$chapter.${first.paragraphIndex + 1}';
}
