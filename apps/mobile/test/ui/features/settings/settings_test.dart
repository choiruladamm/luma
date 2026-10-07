import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/ai_results_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/domain/models/ai_model.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/settings/views/settings_view.dart';

import '../../../fakes.dart';

class FakeAiResults implements AiResultsRepository {
  final stats = StreamController<AiCacheStats>.broadcast();
  int clears = 0;

  @override
  Stream<AiCacheStats> watchStats() => stats.stream;

  @override
  Future<void> clear() async {
    clears++;
    stats.add((paragraphs: 0, bytes: 0));
  }
}

void main() {
  late FakeSettings settings;
  late FakeAiResults cache;

  Future<void> open(
    WidgetTester tester, {
    Brightness b = Brightness.light,
    AiCacheStats stats = (paragraphs: 1240, bytes: 3355443),
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = FakeSettings();
    cache = FakeAiResults();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          aiResultsRepositoryProvider.overrideWithValue(cache),
          // Secure storage goes in-memory via setMockInitialValues.
          apiKeyStoreProvider.overrideWithValue(ApiKeyStore()),
        ],
        child: MaterialApp(theme: stabiloTheme(b), home: const SettingsView()),
      ),
    );
    await tester.pump();
    cache.stats.add(stats);
    await tester.pumpAndSettle();
  }

  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'openrouter_api_key': 'sk-or-v1-saved',
    }),
  );

  for (final b in Brightness.values) {
    testWidgets('shows key (hidden), models, cache ($b)', (tester) async {
      await open(tester, b: b);
      expect(find.text('Pengaturan'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'sk-or-v1-saved');
      expect(field.obscureText, isTrue);
      for (final m in aiModels) {
        expect(find.text(m.label), findsOneWidget);
        expect(find.text(m.id), findsOneWidget);
      }
      expect(find.text('Default · paling hemat'), findsOneWidget);
      expect(find.text('1.240 paragraf · 3,2 MB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('typing a key saves it to the Keychain', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'sk-or-v1-new');
    await tester.pump();
    expect(await ApiKeyStore().read(), 'sk-or-v1-new');
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(await ApiKeyStore().read(), isNull);
  });

  testWidgets('picking a model saves it', (tester) async {
    await open(tester);
    await tester.tap(find.text('Qwen 3.8 Flash'));
    await tester.pumpAndSettle();
    expect(settings.model, 'qwen/qwen3.8-flash');
  });

  testWidgets('clearing the cache asks first', (tester) async {
    await open(tester);
    await tester.tap(find.text('Hapus cache'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(cache.clears, 0);

    await tester.tap(find.text('Hapus cache'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();
    expect(cache.clears, 1);
    expect(find.text('0 paragraf · 0 KB'), findsOneWidget);
  });

  testWidgets('nothing to clear: button is off', (tester) async {
    await open(tester, stats: (paragraphs: 0, bytes: 0));
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Hapus cache'),
    );
    expect(button.onPressed, isNull);
  });
}
