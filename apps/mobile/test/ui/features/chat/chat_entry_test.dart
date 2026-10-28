import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/ui/features/chat/view_models/chat_entry.dart';
import 'package:luma/ui/features/reader/view_models/reader_view_model.dart';

void main() {
  ProviderContainer container() => ProviderContainer(
    overrides: [
      readerBookProvider.overrideWith(
        (ref, id) async => ReaderBook(
          id: id,
          contentRevision: 7,
          title: 'Buku',
          totalChars: 100,
          chapters: const [
            ChapterInfo(id: 10, title: 'Bab', charOffset: 0, chars: 100),
          ],
        ),
      ),
      chapterParagraphsProvider.overrideWith(
        (ref, id) async => const [
          ReaderParagraph(
            index: 0,
            groupIndex: 0,
            type: ParagraphType.paragraph,
            text: 'Sumber pertama 🐈',
          ),
          ReaderParagraph(
            index: 1,
            groupIndex: 0,
            type: ParagraphType.paragraph,
            text: 'Sumber kedua\nlanjutan',
          ),
          ReaderParagraph(
            index: 2,
            groupIndex: 1,
            type: ParagraphType.paragraph,
            text: 'Topik lain',
          ),
        ],
      ),
    ],
  );
  test(
    'quote freezes exact group ranges, hashes and current revision',
    () async {
      final c = container();
      addTearDown(c.dispose);
      final quote = await c.read(
        chatEntryQuoteProvider((
          bookId: 1,
          group: (chapterId: 10, groupIndex: 0),
        )).future,
      );
      expect(quote.anchors.map((a) => a.paragraphIndex), [0, 1]);
      for (final a in quote.anchors) {
        expect(a.book, (bookId: 1, contentRevision: 7));
        expect(a.start, 0);
        expect(a.end, a.snapshot.length);
        a.validate((
          book: a.book,
          chapterId: a.chapterId,
          paragraphIndex: a.paragraphIndex,
          text: a.snapshot,
        ), a.book);
      }
      final next = await c.read(
        chatEntryQuoteProvider((
          bookId: 1,
          group: (chapterId: 10, groupIndex: 1),
        )).future,
      );
      expect(next.text, 'Topik lain');
      expect(quote.text, isNot(contains(next.text)));
    },
  );
  test('quote rejects foreign chapter and missing group', () async {
    final c = container();
    addTearDown(c.dispose);
    for (final group in [
      (chapterId: 999, groupIndex: 0),
      (chapterId: 10, groupIndex: 99),
    ]) {
      await expectLater(
        c.read(chatEntryQuoteProvider((bookId: 1, group: group)).future),
        throwsFormatException,
      );
    }
  });
}
