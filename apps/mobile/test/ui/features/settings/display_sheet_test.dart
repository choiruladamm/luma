import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/domain/models/reader_prefs.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/settings/views/display_sheet.dart';

import '../../../fakes.dart';

void main() {
  late FakeSettings settings;

  Future<void> open(
    WidgetTester tester, {
    Brightness b = Brightness.light,
    bool failLocaleSave = false,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = FakeSettings()..failLocaleSave = failLocaleSave;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale(ref.watch(appLocaleProvider).value ?? 'id'),
            theme: stabiloTheme(b),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDisplaySheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final b in Brightness.values) {
    testWidgets('shows theme + language with board copy (${b.name})', (
      tester,
    ) async {
      await open(tester, b: b);
      expect(find.text('Tampilan'), findsOneWidget);
      expect(find.text('Ikut sistem'), findsOneWidget);
      expect(find.text('Ngikut mode HP'), findsOneWidget);
      expect(find.text('Terang'), findsOneWidget);
      expect(find.text('Gelap'), findsOneWidget);
      expect(
        find.text(
          'Bahasa ini cuma buat tampilan. Terjemahan sama jawaban AI tetap '
          'Bahasa Indonesia.',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('picking a theme saves the same prefs the Aa menu uses', (
    tester,
  ) async {
    await open(tester);
    expect(settings.prefs.theme, AppTheme.system);
    await tester.tap(find.text('Gelap'));
    await tester.pumpAndSettle();
    expect(settings.prefs.theme, AppTheme.dark);
    await tester.tap(find.text('Terang'));
    await tester.pumpAndSettle();
    expect(settings.prefs.theme, AppTheme.light);
  });

  testWidgets('picking English saves it and re-renders in English', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(settings.language, 'en');
    expect(find.text('Display language'), findsOneWidget);
    expect(find.text('Follow system'), findsOneWidget);
  });

  testWidgets('failed language save shows a toast', (tester) async {
    await open(tester, failLocaleSave: true);
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Bahasanya gagal disimpen. Coba lagi, ya.'),
      findsOneWidget,
    );
    expect(settings.language, 'id');
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });
}
