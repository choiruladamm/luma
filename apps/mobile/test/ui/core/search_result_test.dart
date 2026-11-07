import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/search_result.dart';
import 'package:luma/ui/core/widgets/tag.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: stabiloTheme(Brightness.light),
        home: Scaffold(body: SizedBox(width: 340, child: child)),
      ),
    );
  }

  group('SearchGroupHeader', () {
    testWidgets('title, count, and the chip only for the current chapter', (
      tester,
    ) async {
      await pump(
        tester,
        const Column(
          children: [
            SearchGroupHeader(title: 'Chapter I', count: 2, current: true),
            SearchGroupHeader(title: 'Chapter IV', count: 1),
          ],
        ),
      );
      expect(find.text('Chapter I'), findsOneWidget);
      expect(find.text('2 hasil'), findsOneWidget);
      expect(find.text('1 hasil'), findsOneWidget);
      expect(find.byType(Tag), findsOneWidget);
      expect(find.text('Lagi dibaca'), findsOneWidget);
    });

    testWidgets('the count is flush right at any width (justify-between)', (
      tester,
    ) async {
      for (final w in [340.0, 800.0]) {
        tester.view.physicalSize = Size(w, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: stabiloTheme(Brightness.light),
            home: const Scaffold(
              body: Column(
                children: [
                  SearchGroupHeader(
                    title: 'Chapter I',
                    count: 2,
                    current: true,
                  ),
                  SearchGroupHeader(title: 'Chapter IV', count: 1),
                ],
              ),
            ),
          ),
        );
        for (final label in ['2 hasil', '1 hasil']) {
          expect(
            tester.getTopRight(find.text(label)).dx,
            closeTo(w - 4, 0.5),
            reason: '$label at $w',
          );
        }
      }
    });

    testWidgets('a long chapter title ellipsizes instead of overflowing', (
      tester,
    ) async {
      await pump(
        tester,
        SearchGroupHeader(
          title: 'Chapter ${'X' * 80}',
          count: 12,
          current: true,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('12 hasil'), findsOneWidget);
    });
  });

  group('SearchHitTile', () {
    const snippet = 'He did look at Netherfield House and was pleased.';

    testWidgets('highlights exactly the matched word and taps through', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        SearchHitTile(
          snippet: snippet,
          matchStart: 15,
          matchEnd: 26,
          onTap: () => taps++,
        ),
      );
      final rich = tester.widget<RichText>(
        find
            .descendant(
              of: find.byType(SearchHitTile),
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(
        rich.text.toPlainText(includePlaceholders: false),
        contains('He did look at '),
      );
      expect(find.text('Netherfield'), findsOneWidget); // the stabilo span
      await tester.tap(find.byType(SearchHitTile));
      expect(taps, 1);
    });

    testWidgets('0..0 or out of range means no highlight, full text', (
      tester,
    ) async {
      for (final (s, e) in [(0, 0), (5, 999)]) {
        await pump(
          tester,
          SearchHitTile(
            snippet: snippet,
            matchStart: s,
            matchEnd: e,
            onTap: () {},
          ),
        );
        expect(find.text(snippet), findsOneWidget);
      }
    });

    testWidgets('never more than 3 lines', (tester) async {
      await pump(
        tester,
        SearchHitTile(
          snippet: 'word ' * 200,
          matchStart: 0,
          matchEnd: 4,
          onTap: () {},
        ),
      );
      final text = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(SearchHitTile),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(text.maxLines, 3);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });
}
