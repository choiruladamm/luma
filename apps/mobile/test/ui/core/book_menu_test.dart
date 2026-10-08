import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/ui/core/widgets/book_card.dart';
import 'package:luma/ui/core/widgets/book_cover.dart';
import 'package:luma/ui/core/widgets/book_menu.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/core/widgets/menu.dart';

import '../../app.dart';

void main() {
  String? picked;
  var closed = false;

  Widget open() => opener((context) async {
    picked = await showBookMenu<String>(
      context,
      title: 'Dracula',
      author: 'Bram Stoker',
      progress: 0.48,
      opened: true,
      finished: false,
      items: const [
        AppMenuItem('info', 'Info buku', icon: AppIcons.info),
        AppMenuItem(
          'delete',
          'Hapus dari rak',
          icon: AppIcons.delete,
          destructive: true,
        ),
      ],
    );
    closed = true;
  });

  setUp(() {
    picked = null;
    closed = false;
  });

  for (final brightness in Brightness.values) {
    testWidgets('lifted cover, sticker and two rows (${brightness.name})', (
      tester,
    ) async {
      await pumpApp(tester, open(), brightness: brightness);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Board 20: cover 156 wide at top 168, panel 250 wide, rows 52 high.
      final cover = tester.getRect(find.byType(BookCover));
      expect(cover.width, closeTo(Layout.bookMenuCover, 0.5));
      expect(cover.top, Layout.bookMenuTop);
      expect(find.byType(ProgressSticker), findsOneWidget);
      expect(find.text('48%'), findsOneWidget);
      expect(
        tester.getSize(find.text('Info buku').hitTestable()).width,
        lessThan(Layout.bookMenuWidth),
      );
      final row = find.ancestor(
        of: find.text('Info buku'),
        matching: find.byType(ConstrainedBox),
      );
      expect(tester.getSize(row.first).height, Layout.bookMenuRow);
    });
  }

  testWidgets('no debug underline on any text (board 20 has none)', (
    tester,
  ) async {
    await pumpApp(tester, open());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final text in ['Info buku', 'Hapus dari rak', '48%']) {
      final style = DefaultTextStyle.of(tester.element(find.text(text))).style;
      expect(style.decoration, isNot(TextDecoration.underline), reason: text);
    }
    for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
      expect(w.text.style?.decoration, isNot(TextDecoration.underline));
    }
  });

  testWidgets('picking a row returns its value', (tester) async {
    await pumpApp(tester, open());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus dari rak'));
    await tester.pumpAndSettle();
    expect(picked, 'delete');
    expect(find.text('Info buku'), findsNothing);
  });

  testWidgets('tapping outside closes with no value', (tester) async {
    await pumpApp(tester, open());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 1300));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(picked, isNull);
    expect(find.text('Info buku'), findsNothing);
  });
}
