import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/switch.dart';

void main() {
  for (final b in Brightness.values) {
    testWidgets('tap flips the value, 51 × 31 ($b)', (tester) async {
      var value = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: stabiloTheme(b),
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) => AppSwitch(
                  value: value,
                  semanticLabel: 'Tampilin garis progres',
                  onChanged: (v) => setState(() => value = v),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(AppSwitch)), const Size(51, 31));
      await tester.tap(find.byType(AppSwitch));
      await tester.pumpAndSettle();
      expect(value, isFalse);
      expect(
        tester.getSemantics(find.byType(AppSwitch)),
        matchesSemantics(
          label: 'Tampilin garis progres',
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );
    });
  }
}
