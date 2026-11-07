import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/ui/core/widgets/search_navigator.dart';

void main() {
  var prev = 0, next = 0, list = 0, close = 0;

  Future<void> pump(
    WidgetTester tester, {
    bool compact = false,
    int position = 1,
    int total = 68,
    bool truncated = false,
    bool first = false,
    bool last = false,
    String? chapter = 'Chapter I',
    Brightness b = Brightness.light,
  }) async {
    prev = next = list = close = 0;
    tester.view.physicalSize = const Size(780, 1600);
    tester.view.devicePixelRatio = 2; // 390 wide, like the board
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: stabiloTheme(b),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SearchNavigator(
              word: 'Netherfield',
              position: position,
              total: total,
              truncated: truncated,
              chapterTitle: chapter,
              compact: compact,
              onPrevious: first ? null : () => prev++,
              onNext: last ? null : () => next++,
              onList: () => list++,
              onClose: () => close++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Size size(WidgetTester tester) =>
      tester.getSize(find.byType(SearchNavigator));

  testWidgets('full: pill 50 with the word and "1 dari 68 · Chapter I"', (
    tester,
  ) async {
    await pump(tester);
    expect(size(tester).height, Layout.searchNavHeight);
    expect(find.text('Netherfield'), findsOneWidget);
    expect(find.text('1 dari 68 · Chapter I'), findsOneWidget);
    expect(find.text('1/68'), findsNothing);
  });

  testWidgets('compact: pill 46, just "1/68", narrower', (tester) async {
    await pump(tester);
    final full = size(tester).width;
    await pump(tester, compact: true);
    expect(size(tester).height, Layout.searchNavCompactHeight);
    expect(find.text('1/68'), findsOneWidget);
    expect(find.text('Netherfield'), findsNothing);
    // About 40% narrower on the board.
    expect(size(tester).width, lessThan(full * 0.8));
  });

  testWidgets('the four buttons and the middle each call back once', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Hasil sebelumnya'));
    await tester.tap(find.bySemanticsLabel('Hasil berikutnya'));
    await tester.tap(find.bySemanticsLabel('Balik ke daftar hasil'));
    await tester.tap(find.bySemanticsLabel('Keluar dari cari'));
    expect((prev, next, list, close), (1, 1, 1, 1));
  });

  testWidgets('no previous / next = dimmed and silent', (tester) async {
    await pump(tester, first: true, last: true);
    await tester.tap(find.bySemanticsLabel('Hasil sebelumnya'));
    await tester.tap(find.bySemanticsLabel('Hasil berikutnya'));
    expect((prev, next), (0, 0));
  });

  testWidgets('touch targets are 44 even though the circles are 36', (
    tester,
  ) async {
    await pump(tester);
    for (final label in [
      'Hasil sebelumnya',
      'Hasil berikutnya',
      'Keluar dari cari',
    ]) {
      final box = tester.getSize(find.bySemanticsLabel(label));
      expect(box.width, greaterThanOrEqualTo(Layout.touch), reason: label);
      expect(box.height, greaterThanOrEqualTo(Layout.touch), reason: label);
    }
  });

  testWidgets('over 500 hits reads "500+"; no chapter title is fine', (
    tester,
  ) async {
    await pump(tester, total: 500, truncated: true, chapter: null);
    expect(find.text('1 dari 500+'), findsOneWidget);
    await pump(tester, compact: true, total: 500, truncated: true);
    expect(find.text('1/500+'), findsOneWidget);
  });

  testWidgets('a long word or chapter title ellipsizes, never overflows', (
    tester,
  ) async {
    await pump(tester, chapter: 'Chapter ${'XLVIII ' * 12}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode renders', (tester) async {
    await pump(tester, b: Brightness.dark);
    await pump(tester, b: Brightness.dark, compact: true);
    expect(tester.takeException(), isNull);
  });
}
