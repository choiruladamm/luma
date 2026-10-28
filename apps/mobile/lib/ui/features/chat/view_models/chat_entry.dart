import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/book_chat.dart';
import '../../reader/view_models/reader_view_model.dart';

typedef ChatQuoteRequest = ({int bookId, GroupRef group});

/// Read-only imported text; creating an attachment never starts an AI request.
final chatEntryQuoteProvider = FutureProvider.autoDispose
    .family<ChatQuote, ChatQuoteRequest>((ref, request) async {
      final keep = ref.keepAlive();
      try {
        final (book, paragraphs) = await (
          ref.watch(readerBookProvider(request.bookId).future),
          ref.watch(chapterParagraphsProvider(request.group.chapterId).future),
        ).wait;
        if (book == null ||
            !book.chapters.any((c) => c.id == request.group.chapterId)) {
          throw const FormatException('Buku atau bab gak tersedia');
        }
        final own = paragraphs
            .where((p) => p.groupIndex == request.group.groupIndex)
            .toList();
        if (own.isEmpty) throw const FormatException('Kutipan gak tersedia');
        return ChatQuote(
          anchors: [
            for (final p in own)
              SourceAnchor(
                book: (bookId: book.id, contentRevision: book.contentRevision),
                chapterId: request.group.chapterId,
                paragraphIndex: p.index,
                start: 0,
                end: p.text.length,
                paragraphHash: chatTextHash(p.text),
                snapshot: p.text,
              ),
          ],
        );
      } finally {
        keep.close();
      }
    }, retry: (_, _) => null);
