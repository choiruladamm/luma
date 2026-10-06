import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/book_card.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/bookshelf/views/bookshelf_view.dart';
import 'package:luma/ui/features/reader/view_models/reader_view_model.dart';
import 'package:luma/ui/features/reader/views/reader_view.dart';

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

final paragraphs = {
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
  // Feeds the reader through its providers; no Drift in widget tests.
  Future<void> openBook(
    WidgetTester tester, {
    Brightness b = Brightness.light,
  }) async {
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
          readerBookProvider.overrideWith((ref, id) async => book),
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

    pending.complete(paragraphs[10]!);
    await tester.pump();
    expect(find.text('Lanjut, gas'), findsOneWidget);
  });
}
