import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/ui/core/widgets/search_field.dart';

void main() {
  Future<TextEditingController> pump(
    WidgetTester tester, {
    ValueChanged<String>? onChanged,
    Brightness b = Brightness.light,
  }) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: stabiloTheme(b),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: SearchField(
              controller: controller,
              hint: 'Cari kata di buku ini',
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  BoxDecoration decoration(WidgetTester tester) =>
      tester
              .widget<Container>(
                find
                    .descendant(
                      of: find.byType(SearchField),
                      matching: find.byType(Container),
                    )
                    .first,
              )
              .decoration!
          as BoxDecoration;

  testWidgets('is 44 tall and shows the hint', (tester) async {
    await pump(tester);
    expect(tester.getSize(find.byType(SearchField)).height, Layout.searchField);
    expect(find.text('Cari kata di buku ini'), findsOneWidget);
  });

  testWidgets('resting is muted, focus adds the ink outline and yellow ring', (
    tester,
  ) async {
    await pump(tester);
    final rest = decoration(tester);
    expect(rest.border, isNull);
    expect(rest.boxShadow, isNull);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    final focused = decoration(tester);
    expect(focused.border, isNotNull);
    expect((focused.border! as Border).top.width, Layout.outline);
    expect(focused.boxShadow!.single.spreadRadius, Layout.searchRing);
    expect(focused.color, isNot(rest.color));
  });

  testWidgets('× shows only with text and clears it, telling onChanged', (
    tester,
  ) async {
    final seen = <String>[];
    final controller = await pump(tester, onChanged: seen.add);
    expect(find.bySemanticsLabel('Hapus isian'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Netherfield');
    await tester.pump();
    expect(seen, ['Netherfield']);
    await tester.tap(find.bySemanticsLabel('Hapus isian'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(seen, ['Netherfield', '']);
    expect(find.bySemanticsLabel('Hapus isian'), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    await pump(tester, b: Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}
