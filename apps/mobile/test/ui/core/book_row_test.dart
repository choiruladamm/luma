import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/markdown_shelf.dart';
import 'package:luma/ui/core/widgets/book_row.dart';
import 'package:luma/ui/core/widgets/chapter_slots.dart';
import 'package:luma/ui/core/widgets/tag.dart';

import '../../app.dart';

void main() {
  Widget row(MarkdownShelf md, {bool opened = true, String? author}) =>
      SizedBox(
        width: 360,
        child: BookRow(
          title: 'Atomic Habits',
          author: author,
          progress: 0,
          opened: opened,
          finished: false,
          markdown: md,
        ),
      );

  const three = MarkdownShelf(chapters: [1, 3, 7], current: 3, fraction: 0.4);

  for (final b in Brightness.values) {
    testWidgets('markdown row: chapter line, strip, "3 bab" ($b)', (
      tester,
    ) async {
      await pumpApp(tester, row(three), brightness: b);
      expect(find.text('Bab 1, 3, 7'), findsOneWidget); // no author
      expect(find.text('3 bab'), findsOneWidget);
      expect(find.byType(ChapterSlots), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('author wins the second line when the file has one', (
    tester,
  ) async {
    await pumpApp(tester, row(three, author: 'James Clear'));
    expect(find.text('James Clear'), findsOneWidget);
    expect(find.text('Bab 1, 3, 7'), findsNothing);
  });

  testWidgets('never opened: "Baru" replaces the label, strip stays', (
    tester,
  ) async {
    await pumpApp(
      tester,
      row(const MarkdownShelf(chapters: [1]), opened: false),
    );
    expect(find.widgetWithText(Tag, 'Baru'), findsOneWidget);
    expect(find.text('1 bab'), findsNothing);
    expect(find.byType(ChapterSlots), findsOneWidget);
  });

  testWidgets('40 chapters: label ranges, one bar, "40 bab"', (tester) async {
    await pumpApp(
      tester,
      row(
        MarkdownShelf(
          chapters: List.generate(40, (i) => i + 1),
          current: 13,
          fraction: 0.5,
        ),
      ),
    );
    expect(find.text('Bab 1–40'), findsOneWidget);
    expect(find.text('40 bab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('semantics: one label for the whole row', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, row(three));
    expect(
      find.bySemanticsLabel(
        'Atomic Habits, 3 bab, bab 1 udah dibaca, lagi baca bab 3',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
