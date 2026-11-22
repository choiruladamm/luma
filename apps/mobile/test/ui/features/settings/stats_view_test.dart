import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/stats_repository.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/settings/views/stats_view.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    ReadingSummary summary, {
    Brightness b = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readingSummaryProvider.overrideWith((_) => Stream.value(summary)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          theme: stabiloTheme(b),
          home: const StatsView(),
        ),
      ),
    );
    await tester.pump();
  }

  for (final b in Brightness.values) {
    testWidgets('week and all-time numbers ($b)', (tester) async {
      await open(
        tester,
        const ReadingSummary(
          weekSeconds: 4500,
          weekDays: 3,
          totalSeconds: 36000,
          finishedBooks: 2,
        ),
        b: b,
      );
      expect(find.text('Statistik baca'), findsOneWidget);
      expect(find.text('7 hari terakhir'), findsOneWidget);
      expect(find.text('1 jam 15 mnt'), findsOneWidget);
      expect(find.text('3/7'), findsOneWidget);
      expect(find.text('10 jam 0 mnt'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Belum ada statistik'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty state before any reading', (tester) async {
    await open(
      tester,
      const ReadingSummary(
        weekSeconds: 0,
        weekDays: 0,
        totalSeconds: 0,
        finishedBooks: 0,
      ),
    );
    expect(find.text('Belum ada statistik'), findsOneWidget);
    expect(find.text('7 hari terakhir'), findsNothing);
  });
}
