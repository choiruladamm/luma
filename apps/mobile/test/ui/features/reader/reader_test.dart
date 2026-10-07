import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/reading_progress_repository.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/book_card.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/bookshelf/views/bookshelf_view.dart';
import 'package:luma/ui/features/reader/view_models/reader_view_model.dart';
import 'package:luma/ui/features/reader/views/reader_view.dart';

import '../../../fakes.dart';

const book = ReaderBook(
  id: 1,
  title: 'The Enchiridion',
  totalChars: 300,
  chapters: [
    ChapterInfo(id: 10, title: 'I', charOffset: 0, chars: 100),
    ChapterInfo(id: 11, title: 'II', charOffset: 100, chars: 200),
  ],
);

ReaderParagraph p(int i, ParagraphType type, String text, [int? group]) =>
    ReaderParagraph(index: i, groupIndex: group, type: type, text: text);

/// A long chapter to scroll through: paragraph i reads "Line i ...".
final long = [
  for (var i = 0; i < 60; i++)
    p(i, ParagraphType.paragraph, 'Line $i of a long chapter.', i),
];

/// Multi-line paragraphs, so an offset inside one means something.
final tall = [
  for (var i = 0; i < 30; i++)
    p(i, ParagraphType.paragraph, 'Tall $i: ${'word ' * 30}'.trim(), i),
];

final paragraphs = {
  12: long,
  13: tall,
  10: [
    p(0, ParagraphType.heading, 'I'), // same as the chapter title: hidden
    p(
      1,
      ParagraphType.paragraph,
      'There are things which are within our power.',
      0,
    ),
    p(2, ParagraphType.sceneBreak, '***'),
    p(
      3,
      ParagraphType.paragraph,
      'Conduct me, Zeus,\nWherever your decrees',
      1,
    ),
  ],
  11: [
    p(
      0,
      ParagraphType.paragraph,
      'Never say of anything, "I have lost it."',
      0,
    ),
  ],
};

void main() {
  late FakeProgress progress;

  // Feeds the reader through its providers; no Drift in widget tests.
  Future<void> openBook(
    WidgetTester tester, {
    Brightness b = Brightness.light,
    ReaderBook readerBook = book,
    ReadingPosition? saved,
  }) async {
    progress = FakeProgress(saved);
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = b;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksStreamProvider.overrideWith(
            (ref) => Stream.value([
              ShelfBook(
                id: 1,
                title: book.title,
                author: 'Epictetus',
                coverName: null,
                opened: true,
                createdAt: DateTime(2026, 10, 1),
              ),
            ]),
          ),
          readerBookProvider.overrideWith((ref, id) async => readerBook),
          readingProgressRepositoryProvider.overrideWithValue(progress),
          chapterParagraphsProvider.overrideWith(
            (ref, chapterId) async => paragraphs[chapterId]!,
          ),
          chapterTranslatedProvider.overrideWith(
            (ref, chapterId) async => chapterId == 10 ? 3 : 0,
          ),
          bookEndProvider.overrideWith(
            (ref, id) async => BookEnd(
              author: 'Epictetus',
              coverName: null,
              readingSeconds: 6 * 3600 + 20 * 60,
              translated: 86,
            ),
          ),
        ],
        child: const LumaApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();
  }

  for (final b in Brightness.values) {
    testWidgets(
      'reads a chapter: heading, text, scene break, poem lines ($b)',
      (tester) async {
        await openBook(tester, b: b);
        expect(find.byType(ReaderView), findsOneWidget);
        expect(find.text('The Enchiridion'), findsOneWidget); // top bar
        expect(find.text('Bab 1'), findsOneWidget);
        expect(find.text('I'), findsOneWidget); // title shown once, not twice
        expect(
          find.text('There are things which are within our power.'),
          findsOneWidget,
        );
        expect(find.text('* * *'), findsOneWidget);
        expect(
          find.text('Conduct me, Zeus,\nWherever your decrees'),
          findsOneWidget,
        );
        expect(find.textContaining('%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('chapter end card moves on to the next chapter', (tester) async {
    await openBook(tester);
    expect(find.text('Bab 1 kelar'), findsOneWidget);
    expect(find.text('3 paragraf diterjemahin'), findsOneWidget);
    expect(find.text('Lanjut ke II?'), findsOneWidget);
    expect(find.text('Bab 2 dari 2 · ±1 menit'), findsOneWidget);

    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    expect(find.text('Bab 2'), findsOneWidget);
    expect(
      find.text('Never say of anything, "I have lost it."'),
      findsOneWidget,
    );
    // Nothing translated here yet: no count.
    expect(find.textContaining('diterjemahin'), findsNothing);
    expect(find.text('Itu tadi bab terakhir!'), findsOneWidget);
  });

  for (final b in Brightness.values) {
    testWidgets('the last chapter leads to the book end screen ($b)', (
      tester,
    ) async {
      await openBook(tester, b: b);
      await tester.tap(find.text('Lanjut, gas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut, gas'));
      await tester.pumpAndSettle();

      expect(find.text('kelar!'), findsOneWidget);
      expect(
        find.text(
          'The Enchiridion udah lo libas sampe kalimat terakhir. Keren sih.',
        ),
        findsOneWidget,
      );
      expect(find.text('6 jam 20 mnt'), findsOneWidget);
      expect(find.text('86'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('book end: read again from the start, or back to the shelf', (
    tester,
  ) async {
    await openBook(tester);
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Baca ulang dari awal'));
    await tester.pumpAndSettle();
    expect(find.text('Bab 1'), findsOneWidget);
    expect(progress.saves.last, (
      chapterId: 10,
      paragraphIndex: 0,
      paragraphOffset: 0.0,
    ));

    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Balik ke rak, cari buku lain'));
    await tester.pumpAndSettle();
    expect(find.byType(BookshelfView), findsOneWidget);

    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderView), findsNothing);
  });

  testWidgets('back button and "Udahan dulu" return to the shelf', (
    tester,
  ) async {
    await openBook(tester);
    await tester.tap(find.text('Udahan dulu, balik ke rak'));
    await tester.pumpAndSettle();
    expect(find.byType(BookshelfView), findsOneWidget);
    expect(find.byType(ReaderView), findsNothing);

    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Balik ke rak'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderView), findsNothing);
  });

  testWidgets('Aa stays off until #18 lands', (tester) async {
    await openBook(tester);
    final button = tester.widget<CircleButton>(
      find.byWidgetPredicate(
        (w) => w is CircleButton && w.semanticLabel == 'Atur tampilan teks',
      ),
    );
    expect(button.onPressed, isNull);
  });

  Future<void> openToc(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Daftar isi'));
    await tester.pumpAndSettle();
  }

  testWidgets('contents sheet: header, current chapter, jump to another', (
    tester,
  ) async {
    await openBook(tester);
    await openToc(tester);
    expect(find.text('Daftar isi'), findsOneWidget);
    expect(find.textContaining('The Enchiridion · 2 bab · '), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('Lagi dibaca'), findsOneWidget);

    await tester.tap(find.text('II').last);
    await tester.pumpAndSettle();
    expect(find.text('Daftar isi'), findsNothing);
    expect(find.text('Bab 2'), findsOneWidget);
    expect(progress.saves.last, (
      chapterId: 11,
      paragraphIndex: 0,
      paragraphOffset: 0.0,
    ));
  });

  testWidgets('closing the contents keeps the chapter', (tester) async {
    await openBook(tester);
    await openToc(tester);
    progress.saves.clear();
    await tester.tap(find.bySemanticsLabel('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('Bab 1'), findsOneWidget);
    expect(progress.saves, isEmpty);
  });

  testWidgets('a long contents list scrolls to the current chapter', (
    tester,
  ) async {
    final many = ReaderBook(
      id: 1,
      title: 'Big Book',
      totalChars: 6000,
      chapters: [
        for (var i = 0; i < 60; i++)
          ChapterInfo(
            id: 100 + i,
            title: 'Chapter ${i + 1}',
            charOffset: i * 100,
            chars: 100,
          ),
      ],
    );
    paragraphs[140] = [p(0, ParagraphType.paragraph, 'Deep in the book.', 0)];
    await openBook(
      tester,
      readerBook: many,
      saved: (chapterId: 140, paragraphIndex: 0, paragraphOffset: 0.0),
    );
    await openToc(tester);
    final badge = find.text('Lagi dibaca');
    expect(badge, findsOneWidget);
    final sheet = tester.getRect(find.byType(BottomSheet));
    final row = tester.getRect(badge);
    expect(sheet.contains(row.center), isTrue); // scrolled into view
  });

  testWidgets('while the text loads, only the heading shows (no end card)', (
    tester,
  ) async {
    final pending = Completer<List<ReaderParagraph>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readerBookProvider.overrideWith((ref, id) async => book),
          readingProgressRepositoryProvider.overrideWithValue(FakeProgress()),
          chapterParagraphsProvider.overrideWith((ref, id) => pending.future),
          chapterTranslatedProvider.overrideWith((ref, id) async => 0),
        ],
        child: MaterialApp(
          theme: stabiloTheme(Brightness.light),
          home: const ReaderView(bookId: 1),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Bab 1'), findsOneWidget);
    expect(find.text('Lanjut, gas'), findsNothing);

    double opacity() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    expect(opacity(), 0); // hidden until loaded and in place

    pending.complete(paragraphs[10]!);
    await tester.pumpAndSettle();
    expect(find.text('Lanjut, gas'), findsOneWidget);
    expect(opacity(), 1);
  });

  const longBook = ReaderBook(
    id: 1,
    title: 'The Enchiridion',
    totalChars: 3000,
    chapters: [
      ChapterInfo(id: 10, title: 'I', charOffset: 0, chars: 100),
      ChapterInfo(id: 12, title: 'XXXIII', charOffset: 100, chars: 2900),
    ],
  );

  testWidgets('opening marks the book opened and starts at chapter 1', (
    tester,
  ) async {
    await openBook(tester);
    expect(progress.opened, [1]);
    expect(find.text('Bab 1'), findsOneWidget);
  });

  testWidgets('reopens at the saved chapter and paragraph', (tester) async {
    await openBook(
      tester,
      readerBook: longBook,
      saved: (chapterId: 12, paragraphIndex: 20, paragraphOffset: 0.0),
    );
    expect(find.text('Bab 2'), findsOneWidget);
    // A third down the screen, so there's context above it.
    final line = tester.getTopLeft(find.text('Line 20 of a long chapter.')).dy;
    expect(line, closeTo(1600 / 3, 1));
  });

  const tallBook = ReaderBook(
    id: 1,
    title: 'The Enchiridion',
    totalChars: 3000,
    chapters: [
      ChapterInfo(id: 10, title: 'I', charOffset: 0, chars: 100),
      ChapterInfo(id: 13, title: 'Tall', charOffset: 100, chars: 2900),
    ],
  );

  /// Where [spot] sits on screen: paragraph top + offset × its height.
  double spotY(WidgetTester tester, ReadingPosition spot) {
    final rect = tester.getRect(
      find.textContaining('Tall ${spot.paragraphIndex}:'),
    );
    return rect.top + spot.paragraphOffset * rect.height;
  }

  testWidgets('save → close → reopen lands on the same point', (tester) async {
    await openBook(
      tester,
      readerBook: tallBook,
      saved: (chapterId: 13, paragraphIndex: 0, paragraphOffset: 0.0),
    );
    progress.saves.clear();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1234),
    );
    await tester.pumpAndSettle();
    expect(progress.saves, isEmpty); // not on every frame, not right away
    await tester.pump(const Duration(milliseconds: 500));
    expect(progress.saves, hasLength(1));
    final saved = progress.saves.single;
    expect(saved.paragraphOffset, inExclusiveRange(0, 1));
    // The saved point is where the reading area starts.
    final top = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
    expect(spotY(tester, saved), closeTo(top, 1));

    await tester.tap(find.bySemanticsLabel('Balik ke rak'));
    await tester.pumpAndSettle();
    await openBook(tester, readerBook: tallBook, saved: saved);
    expect(spotY(tester, saved), closeTo(1600 / 3, 1));

    // Leaving without scrolling keeps the same spot.
    await tester.tap(find.bySemanticsLabel('Balik ke rak'));
    await tester.pumpAndSettle();
    expect(progress.saves.last, saved);
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('a bigger font keeps the paragraph and fraction (x$scale)', (
      tester,
    ) async {
      // Straight into the reader: the shelf isn't part of this.
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const saved = (chapterId: 13, paragraphIndex: 12, paragraphOffset: 0.4);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readerBookProvider.overrideWith((ref, id) async => tallBook),
            readingProgressRepositoryProvider.overrideWithValue(
              FakeProgress(saved),
            ),
            chapterParagraphsProvider.overrideWith(
              (ref, id) async => paragraphs[id]!,
            ),
            chapterTranslatedProvider.overrideWith((ref, id) async => 0),
          ],
          child: MaterialApp(
            theme: stabiloTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const ReaderView(bookId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(spotY(tester, saved), closeTo(1600 / 3, 1));
    });
  }

  testWidgets('the last paragraph of a chapter restores without overshoot', (
    tester,
  ) async {
    const saved = (chapterId: 13, paragraphIndex: 29, paragraphOffset: 0.9);
    await openBook(tester, readerBook: tallBook, saved: saved);
    expect(find.textContaining('Tall 29:'), findsOneWidget);
    final rect = tester.getRect(find.textContaining('Tall 29:'));
    expect(rect.top, inInclusiveRange(0, 1600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a one-paragraph chapter restores in place', (tester) async {
    const saved = (chapterId: 11, paragraphIndex: 0, paragraphOffset: 0.5);
    await openBook(tester, saved: saved);
    expect(
      find.text('Never say of anything, "I have lost it."'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Balik ke rak'));
    await tester.pumpAndSettle();
    expect(progress.saves.last, saved);
  });

  testWidgets('a saved chapter that no longer exists falls back to chapter 1', (
    tester,
  ) async {
    await openBook(
      tester,
      saved: (chapterId: 999, paragraphIndex: 3, paragraphOffset: 0.0),
    );
    expect(find.text('Bab 1'), findsOneWidget);
  });

  testWidgets('scrolling saves the top paragraph once it stops', (
    tester,
  ) async {
    await openBook(
      tester,
      readerBook: longBook,
      saved: (chapterId: 12, paragraphIndex: 0, paragraphOffset: 0.0),
    );
    progress.saves.clear();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    final last = progress.saves.last;
    expect(last.chapterId, 12);
    expect(last.paragraphIndex, greaterThan(5));
    // The saved paragraph is the one at the top of the reading area.
    final top = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
    final rect = tester.getRect(
      find.text('Line ${last.paragraphIndex} of a long chapter.'),
    );
    expect(rect.bottom, greaterThan(top));
  });

  testWidgets('moving to the next chapter and leaving both save', (
    tester,
  ) async {
    await openBook(tester);
    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    expect(progress.saves.last, (
      chapterId: 11,
      paragraphIndex: 0,
      paragraphOffset: 0.0,
    ));

    progress.saves.clear();
    await tester.tap(find.bySemanticsLabel('Balik ke rak'));
    await tester.pumpAndSettle();
    expect(progress.saves.last.chapterId, 11);
  });
}
