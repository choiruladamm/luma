import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/tag.dart';

void main() {
  testWidgets('a tag is as wide as its text, not its parent', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: stabiloTheme(Brightness.dark),
        home: const Scaffold(
          body: SizedBox(
            width: 600,
            // Like a sheet section: loose width, start-aligned.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tag.section('Terjemahan'),
                Tag.section('Maksud penulisnya tuh...', tone: TagTone.pink),
                Tag.status('72%'),
              ],
            ),
          ),
        ),
      ),
    );
    for (final tag in tester.widgetList<Tag>(find.byType(Tag))) {
      final box = tester.getSize(find.byWidget(tag));
      final text = tester.getSize(
        find.descendant(of: find.byWidget(tag), matching: find.byType(Text)),
      );
      expect(box.width, lessThan(600));
      // Text plus the side padding, nothing more.
      expect(
        box.width,
        closeTo(text.width + (tag.label == '72%' ? 16 : 20), 0.5),
      );
    }
  });

  testWidgets('also when the parent forces full width (Column stretch)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: stabiloTheme(Brightness.light),
        home: const Scaffold(
          body: SizedBox(
            width: 600,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Tag.section('Terjemahan'),
                Tag.section('Maksud penulisnya tuh...', tone: TagTone.pink),
              ],
            ),
          ),
        ),
      ),
    );
    // The pill (the Tag's own box stays as wide as the parent forces).
    final pills = find.descendant(
      of: find.byType(Tag),
      matching: find.byType(Container),
    );
    expect(pills, findsNWidgets(2));
    for (final pill in pills.evaluate()) {
      expect(tester.getSize(find.byWidget(pill.widget)).width, lessThan(400));
    }
  });
}
