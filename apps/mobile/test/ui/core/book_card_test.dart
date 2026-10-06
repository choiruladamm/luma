import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/widgets/book_card.dart';

import '../../app.dart';

void main() {
  test('sticker label per state', () {
    String s(double p, {bool opened = true, bool finished = false}) =>
        bookSticker(progress: p, opened: opened, finished: finished);
    expect(s(0, opened: false), 'Baru');
    expect(s(0), '0%');
    expect(s(0.004), '1%'); // 0,4% still shows
    expect(s(0.489), '48%'); // rounded down
    expect(s(0.999), '99%');
    expect(s(1), '99%'); // only the last page makes it "Kelar!"
    expect(s(0.7, finished: true), 'Kelar!');
  });

  Widget card({VoidCallback? onTap, VoidCallback? onLongPress}) => SizedBox(
    width: 105,
    child: BookCard(
      title: 'Dracula',
      author: 'Bram Stoker',
      progress: 0.48,
      opened: true,
      finished: false,
      onTap: onTap,
      onLongPress: onLongPress,
    ),
  );

  testWidgets('card: height, sticker, title and author', (tester) async {
    await pumpApp(tester, card());
    expect(find.text('48%'), findsOneWidget);
    expect(find.text('Dracula'), findsOneWidget);
    expect(find.text('Bram Stoker'), findsNWidgets(2)); // on the cover + below
    expect(
      tester.getSize(find.byType(BookCard)).height,
      BookCard.heightFor(105),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap opens; holding 350 ms then releasing opens the menu', (
    tester,
  ) async {
    var taps = 0, menus = 0;
    await pumpApp(
      tester,
      card(onTap: () => taps++, onLongPress: () => menus++),
    );
    await tester.tap(find.byType(BookCard));
    expect((taps, menus), (1, 0));

    final g = await tester.startGesture(
      tester.getCenter(find.byType(BookCard)),
    );
    await tester.pump(const Duration(milliseconds: 360));
    expect(menus, 0); // menu waits for release
    await g.up();
    await tester.pumpAndSettle();
    expect((taps, menus), (1, 1));
  });

  testWidgets('importing card shows the file name and ignores taps', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const SizedBox(
        width: 105,
        child: BookCard.importing(fileName: 'the-republic.epub'),
      ),
    );
    expect(find.text('the-republic.epub'), findsOneWidget);
    expect(find.text('Lagi diproses'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BookCard),
        matching: find.byType(RawGestureDetector),
      ),
      findsNothing,
    );
  });

  testWidgets('finished and new books in dark mode', (tester) async {
    await pumpApp(
      tester,
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 105,
            child: BookCard(
              title: 'Meditations',
              progress: 0,
              opened: false,
              finished: false,
            ),
          ),
          SizedBox(
            width: 105,
            child: BookCard(
              title: 'Emma',
              progress: 1,
              opened: true,
              finished: true,
            ),
          ),
        ],
      ),
      brightness: Brightness.dark,
    );
    expect(find.text('Baru'), findsOneWidget);
    expect(find.text('Kelar!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
