import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/widgets/field.dart';

import '../../app.dart';

void main() {
  testWidgets('secret field hides the key until "Liat key"', (tester) async {
    final controller = TextEditingController(text: 'sk-or-v1-abc');
    addTearDown(controller.dispose);
    await pumpApp(
      tester,
      SizedBox(
        width: 400,
        child: AppField(
          label: 'API key OpenRouter',
          controller: controller,
          secret: true,
        ),
      ),
    );
    bool obscured() =>
        tester.widget<TextField>(find.byType(TextField)).obscureText;

    expect(obscured(), isTrue);
    await tester.tap(find.bySemanticsLabel('Liat key'));
    await tester.pump();
    expect(obscured(), isFalse);
    expect(find.bySemanticsLabel('Sembunyiin key'), findsOneWidget);
  });
}
