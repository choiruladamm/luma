import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/ui/core/widgets/nav_bar.dart';

import '../../app.dart';

void main() {
  for (final b in Brightness.values) {
    testWidgets('three tabs, active one carries its label ($b)', (
      tester,
    ) async {
      LumaTab? tapped;
      await pumpApp(
        tester,
        LumaNavBar(current: LumaTab.rak, onTap: (t) => tapped = t),
        brightness: b,
      );
      expect(find.text('Rak'), findsOneWidget);
      expect(find.text('Cari buku'), findsNothing); // idle: icon only
      expect(find.bySemanticsLabel('Cari buku'), findsOneWidget);
      expect(find.bySemanticsLabel('Atur'), findsOneWidget);
      expect(tester.getSize(find.byType(LumaNavBar)).height, Layout.navBar);

      await tester.tap(find.bySemanticsLabel('Atur'));
      expect(tapped, LumaTab.atur);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('badge on Cari buku reads the count out loud', (tester) async {
    await pumpApp(
      tester,
      LumaNavBar(current: LumaTab.cari, onTap: (_) {}, downloads: 2),
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.bySemanticsLabel('Cari buku, 2 unduhan jalan'), findsOneWidget);
    expect(find.text('Cari buku'), findsOneWidget);
  });
}
