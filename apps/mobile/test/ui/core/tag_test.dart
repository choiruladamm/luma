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
}
