import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/book_search_index.dart';
import 'package:luma/data/repositories/book_search_repository.dart';
import 'package:luma/domain/models/book_search.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/ui/core/widgets/search_result.dart';
import 'package:luma/ui/core/widgets/tag.dart';
import 'package:luma/ui/features/reader/view_models/book_search_view_model.dart';
import 'package:luma/ui/features/reader/views/book_search_sheet.dart';

import '../../../fakes.dart';

void main() {
  late FakeBookSearch repo;
  late FakeSearchIndex index;
  BookSearchPick? picked;
  var closed = false;

  final netherfield = fakeResult([
    (
      10,
      'Chapter I',
      [
        fakeHit(
          10,
          2,
          '“My dear Mr. Bennet,” said his lady, “have you heard that Netherfield Park is let at last?”',
          match: 'Netherfield',
        ),
        fakeHit(
          10,
          5,
          'Mrs. Long says that Netherfield is taken',
          match: 'Netherfield',
        ),
      ],
    ),
    (
      14,
      'Chapter IV',
      [fakeHit(14, 1, 'to look at Netherfield House.', match: 'Netherfield')],
    ),
  ]);

  setUp(() {
    repo = FakeBookSearch(
      results: {'netherfield': netherfield},
      recents: ['Mr. Darcy', 'entailed'],
    );
    index = FakeSearchIndex();
    picked = null;
    closed = false;
  });

  Future<void> open(
    WidgetTester tester, {
    Brightness b = Brightness.light,
    int? currentChapterId = 10,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookSearchRepositoryProvider.overrideWithValue(repo),
          bookSearchIndexProvider.overrideWithValue(index),
        ],
        child: MaterialApp(
          theme: stabiloTheme(b),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    picked = await showBookSearchSheet(
                      context,
                      bookId: 1,
                      currentChapterId: currentChapterId,
                    );
                    closed = true;
                  },
                  child: const Text('buka'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(BookSearchViewModel.debounce);
    await tester.pumpAndSettle();
  }

  testWidgets('1: opens focused with the recents (Terakhir dicari)', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Cari kata di buku ini'), findsOneWidget);
    expect(find.text('Terakhir dicari'), findsOneWidget);
    expect(find.text('Mr. Darcy'), findsOneWidget);
    expect(find.text('entailed'), findsOneWidget);
    expect(find.text('Hapus'), findsOneWidget);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    // Sheet is the full detent: top 54 from the screen top.
    expect(
      tester.getTopLeft(find.byType(BottomSheet)).dy,
      closeTo(1600 - (1600 - Layout.searchSheetTop), 1),
    );
  });

  testWidgets('1: a book with no history shows no list', (tester) async {
    repo = FakeBookSearch();
    await open(tester);
    expect(find.text('Terakhir dicari'), findsNothing);
  });

  testWidgets(
    'Hapus clears the recents, a recent fills the field and searches',
    (tester) async {
      repo = FakeBookSearch(
        results: {'netherfield': netherfield},
        recents: ['Netherfield', 'entailed'],
      );
      await open(tester);
      await tester.tap(find.text('Netherfield'));
      await tester.pumpAndSettle();
      expect(repo.searches, ['Netherfield']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Netherfield',
      );
      expect(find.text('3 hasil di 2 bab'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Hapus isian'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();
      expect(repo.recents, isEmpty);
      expect(find.text('Terakhir dicari'), findsNothing);
    },
  );

  testWidgets('3: results by chapter, count, current chapter chip, stabilo', (
    tester,
  ) async {
    await open(tester);
    await type(tester, 'Netherfield');
    expect(find.text('3 hasil di 2 bab'), findsOneWidget);
    expect(find.text('Chapter I'), findsOneWidget);
    expect(find.text('Chapter IV'), findsOneWidget);
    expect(find.text('2 hasil'), findsOneWidget);
    expect(find.text('1 hasil'), findsOneWidget);
    // Only the chapter being read gets the chip.
    expect(find.widgetWithText(Tag, 'Lagi dibaca'), findsOneWidget);
    // One highlighted word per hit.
    expect(find.byType(SearchHitTile), findsNWidgets(3));
    final marks = find.descendant(
      of: find.byType(SearchHitTile),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == const Color(0xFFFFD84D),
      ),
    );
    expect(marks, findsNWidgets(3));
    for (final m in marks.evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(m.widget),
          matching: find.text('Netherfield'),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('3: no chip when the book has no current chapter yet', (
    tester,
  ) async {
    await open(tester, currentChapterId: null);
    await type(tester, 'Netherfield');
    expect(find.text('Lagi dibaca'), findsNothing);
  });

  testWidgets('3: dark mode renders the same results', (tester) async {
    await open(tester, b: Brightness.dark);
    await type(tester, 'Netherfield');
    expect(find.byType(SearchHitTile), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('3: more than 500 shows the hint', (tester) async {
    repo = FakeBookSearch(
      results: {
        'netherfield': fakeResult([
          (
            10,
            'Chapter I',
            [fakeHit(10, 1, 'Netherfield', match: 'Netherfield')],
          ),
        ], total: 1234),
      },
    );
    await open(tester);
    await type(tester, 'Netherfield');
    expect(find.text('1234 hasil di 1 bab'), findsOneWidget);
    expect(
      find.text('Kebanyakan, coba kata yang lebih spesifik'),
      findsOneWidget,
    );
  });

  testWidgets('4: no match', (tester) async {
    await open(tester);
    await type(tester, 'Netherfeild');
    expect(find.text('Gak ketemu “Netherfeild” di buku ini'), findsOneWidget);
    expect(find.text('Cek ejaannya, atau coba kata lain.'), findsOneWidget);
  });

  testWidgets('5: unindexed book shows the preparing screen, then recents', (
    tester,
  ) async {
    index = FakeSearchIndex(indexed: false, chapters: 61, hold: true);
    await open(tester);
    expect(find.text('Nyiapin pencarian…'), findsOneWidget);
    expect(
      find.text('Cuma sekali buat buku ini. Abis ini nyarinya langsung kilat.'),
      findsOneWidget,
    );
    expect(find.text('Bab 31 dari 61'), findsOneWidget);
    expect(find.text('49%'), findsOneWidget);
    expect(find.text('Terakhir dicari'), findsNothing);

    index.release();
    await tester.pumpAndSettle();
    expect(find.text('Nyiapin pencarian…'), findsNothing);
    expect(find.text('Terakhir dicari'), findsOneWidget);
  });

  testWidgets('tapping a hit remembers the query and returns the hit', (
    tester,
  ) async {
    await open(tester);
    await type(tester, '  Netherfield ');
    await tester.tap(find.byType(SearchHitTile).at(2));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(picked!.query, 'Netherfield');
    expect(picked!.hit.chapterId, 14);
    expect(picked!.hit.paragraphIndex, 1);
    expect(picked!.result.total, 3);
    expect(repo.recents.first, 'Netherfield');
  });

  testWidgets('Batal closes without a result', (tester) async {
    await open(tester);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(picked, isNull);
  });

  testWidgets('× in the field clears it and goes back to the recents', (
    tester,
  ) async {
    await open(tester);
    await type(tester, 'Netherfield');
    await tester.tap(find.bySemanticsLabel('Hapus isian'));
    await tester.pump(BookSearchViewModel.debounce);
    await tester.pumpAndSettle();
    expect(find.text('Terakhir dicari'), findsOneWidget);
    expect(find.byType(SearchHitTile), findsNothing);
  });

  testWidgets('keyboard up: the list shrinks above it, nothing overflows', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.resetViewInsets);
    await open(tester);
    await type(tester, 'Netherfield');
    expect(find.byType(SearchHitTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('huge text size and a short landscape screen do not overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.viewInsets = const FakeViewPadding(bottom: 160);
    addTearDown(tester.view.resetViewInsets);
    await open(tester);
    tester.view.physicalSize = const Size(1688, 780);
    await tester.pumpAndSettle();
    await type(tester, 'Netherfield');
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'Netherfeild');
    await tester.pump(BookSearchViewModel.debounce);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a broken search says so instead of showing nothing', (
    tester,
  ) async {
    repo.failWith = StateError('boom');
    await open(tester);
    await type(tester, 'Netherfield');
    expect(find.text('Pencariannya lagi macet'), findsOneWidget);
  });
}
