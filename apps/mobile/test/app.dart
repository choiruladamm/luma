import 'package:luma/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';

/// Pumps [child] inside a themed MaterialApp + Scaffold. Tests render with
/// Ahem (1em per glyph), so the view is widened to dodge fake overflows.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('id'),
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: stabiloTheme(brightness),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// A button that runs [onTap] with a context under the Scaffold, for opening
/// sheets, dialogs, menus and toasts.
Widget opener(void Function(BuildContext context) onTap) => Builder(
  builder: (context) =>
      TextButton(onPressed: () => onTap(context), child: const Text('open')),
);
