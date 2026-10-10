import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/markdown_shelf.dart';
import 'package:luma/ui/core/widgets/book_card.dart';
import 'package:luma/ui/core/widgets/chapter_slots.dart';

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

  test(
    'markdown sticker: "N bab" replaces the percent, "Baru" still first',
    () {
      String s({required bool opened, int? chapters}) => bookSticker(
        progress: 0.5,
        opened: opened,
        finished: false,
        chapters: chapters,
      );
      expect(s(opened: true, chapters: 3), '3 bab');
      expect(s(opened: false, chapters: 3), 'Baru');
      expect(s(opened: true), '50%');
    },
  );

  for (final b in Brightness.values) {
    testWidgets('markdown card: strip + "3 bab", no percent ($b)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        SizedBox(
          width: 105,
          child: BookCard(
            title: 'Atomic Habits',
            progress: 0.4,
            opened: true,
            finished: false,
            markdown: const MarkdownShelf(
              chapters: [1, 3, 7],
              current: 3,
              fraction: 0.4,
            ),
          ),
        ),
        brightness: b,
      );
      expect(find.text('3 bab'), findsOneWidget);
      expect(find.text('40%'), findsNothing);
      expect(find.byType(ChapterSlots), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Atomic Habits, 3 bab, bab 1 udah dibaca, lagi baca bab 3',
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(BookCard)).height,
        BookCard.heightFor(105), // card height does not change
      );
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  }

  testWidgets('markdown card, never opened: "Baru", strip stays', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const SizedBox(
        width: 105,
        child: BookCard(
          title: 'Deep Work',
          progress: 0,
          opened: false,
          finished: false,
          markdown: MarkdownShelf(chapters: [1]),
        ),
      ),
    );
    expect(find.text('Baru'), findsOneWidget);
    expect(find.text('1 bab'), findsNothing);
    expect(find.byType(ChapterSlots), findsOneWidget);
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
