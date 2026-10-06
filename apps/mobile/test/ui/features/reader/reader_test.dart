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

final paragraphs = {
  12: long,
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

  testWidgets('chapter end card moves on; the last chapter has none', (
    tester,
  ) async {
    await openBook(tester);
    expect(find.text('Lanjut ke II?'), findsOneWidget);
    expect(find.text('Bab 2 dari 2 · ±1 menit'), findsOneWidget);

    await tester.tap(find.text('Lanjut, gas'));
    await tester.pumpAndSettle();
    expect(find.text('Bab 2'), findsOneWidget);
    expect(
      find.text('Never say of anything, "I have lost it."'),
      findsOneWidget,
    );
    expect(find.text('Lanjut, gas'), findsNothing);
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

  testWidgets('contents & Aa stay off until their issues land', (tester) async {
    await openBook(tester);
    for (final label in ['Daftar isi', 'Atur tampilan teks']) {
      final button = tester.widget<CircleButton>(
        find.byWidgetPredicate(
          (w) => w is CircleButton && w.semanticLabel == label,
        ),
      );
      expect(button.onPressed, isNull, reason: label);
    }
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
      saved: (chapterId: 12, paragraphIndex: 20),
    );
    expect(find.text('Bab 2'), findsOneWidget);
    final top = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
    final line = tester.getTopLeft(find.text('Line 20 of a long chapter.')).dy;
    expect(line - top, lessThan(80)); // at the top of the reading area
  });

  testWidgets('a saved chapter that no longer exists falls back to chapter 1', (
    tester,
  ) async {
    await openBook(tester, saved: (chapterId: 999, paragraphIndex: 3));
    expect(find.text('Bab 1'), findsOneWidget);
  });

  testWidgets('scrolling saves the top paragraph once it stops', (
    tester,
  ) async {
    await openBook(
      tester,
      readerBook: longBook,
      saved: (chapterId: 12, paragraphIndex: 0),
    );
    progress.saves.clear();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
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
    expect(progress.saves.last, (chapterId: 11, paragraphIndex: 0));

    progress.saves.clear();
    await tester.tap(find.bySemanticsLabel('Balik ke rak'));
    await tester.pumpAndSettle();
    expect(progress.saves.last.chapterId, 11);
  });
}
