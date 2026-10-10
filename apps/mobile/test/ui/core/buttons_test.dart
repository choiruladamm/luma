import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/widgets/buttons.dart';

import '../../app.dart';

void main() {
  for (final b in Brightness.values) {
    testWidgets('primary taps, disabled does not ($b)', (tester) async {
      var taps = 0;
      await pumpApp(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton.primary(label: 'Lanjut', onPressed: () => taps++),
            const AppButton.primary(label: 'Mati', onPressed: null),
            AppButton.secondary(label: 'Salin', onPressed: () => taps++),
            AppButton.danger(label: 'Hapus', onPressed: () => taps++),
          ],
        ),
        brightness: b,
      );
      for (final l in ['Lanjut', 'Mati', 'Salin', 'Hapus']) {
        await tester.tap(find.text(l));
      }
      expect(taps, 3);
    });
  }

  testWidgets('loading: spinner, same width, no taps', (tester) async {
    var taps = 0;
    Widget button({required bool loading}) => Center(
      child: AppButton.danger(
        label: 'Ganti',
        loading: loading,
        onPressed: () => taps++,
      ),
    );
    await pumpApp(tester, button(loading: false));
    final width = tester.getSize(find.byType(AppButton)).width;
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await pumpApp(tester, button(loading: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(AppButton)).width, width);
    await tester.tap(find.byType(AppButton), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('circle button exposes its label, not its glyph', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(
      tester,
      CircleButton(
        semanticLabel: 'Atur tampilan teks',
        text: 'Aa',
        onPressed: () {},
      ),
    );
    expect(find.bySemanticsLabel('Atur tampilan teks'), findsOneWidget);
    expect(find.bySemanticsLabel('Aa'), findsNothing);
    handle.dispose();
  });
}
