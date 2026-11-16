import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/ai_breakdowns_repository.dart';
import 'package:luma/data/repositories/ai_results_repository.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/settings/views/cache_sheet.dart';

class _Results extends Fake implements AiResultsRepository {
  final stats = StreamController<AiCacheStats>.broadcast();
  int clears = 0;

  @override
  Stream<AiCacheStats> watchStats() => stats.stream;

  @override
  Future<void> clear() async => clears++;
}

class _Breakdowns extends Fake implements AiBreakdownsRepository {
  int clears = 0;

  @override
  Future<void> clear() async => clears++;
}

void main() {
  late _Results results;
  late _Breakdowns breakdowns;

  Future<void> open(
    WidgetTester tester, {
    Brightness b = Brightness.light,
    AiCacheStats stats = (paragraphs: 1240, bytes: 3355443),
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    results = _Results();
    breakdowns = _Breakdowns();
    addTearDown(() => unawaited(results.stats.close()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiResultsRepositoryProvider.overrideWithValue(results),
          aiBreakdownsRepositoryProvider.overrideWithValue(breakdowns),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          theme: stabiloTheme(b),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCacheSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    results.stats.add(stats);
    await tester.pumpAndSettle();
  }

  for (final b in Brightness.values) {
    testWidgets('shows what is stored (${b.name})', (tester) async {
      await open(tester, b: b);
      expect(find.text('Hapus cache terjemahan?'), findsOneWidget);
      expect(find.text('1.240'), findsOneWidget);
      expect(find.text('3,2 MB'), findsOneWidget);
      expect(find.text('paragraf'), findsOneWidget);
    });
  }

  testWidgets('Batal closes without deleting', (tester) async {
    await open(tester);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Hapus cache terjemahan?'), findsNothing);
    expect(results.clears, 0);
    expect(breakdowns.clears, 0);
  });

  testWidgets('Hapus cache clears results and Bedahin, then closes', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Hapus cache'));
    await tester.pumpAndSettle();
    expect(results.clears, 1);
    expect(breakdowns.clears, 1);
    expect(find.text('Hapus cache terjemahan?'), findsNothing);
  });

  testWidgets('nothing stored: Hapus cache is off', (tester) async {
    await open(tester, stats: (paragraphs: 0, bytes: 0));
    await tester.tap(find.text('Hapus cache'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(results.clears, 0);
    expect(find.text('Hapus cache terjemahan?'), findsOneWidget);
  });
}
