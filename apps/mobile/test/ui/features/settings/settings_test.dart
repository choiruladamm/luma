import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/ai_results_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/models/ai_model.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/core/widgets/edge_fade.dart';
import 'package:luma/ui/features/settings/views/settings_view.dart';

import '../../../fakes.dart';

class FakeAiResults extends Fake implements AiResultsRepository {
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
  late FakeOpenRouter openRouter;

  Future<void> open(
    WidgetTester tester, {
    Brightness b = Brightness.light,
    AiCacheStats stats = (paragraphs: 1240, bytes: 3355443),
    bool? keyOk = true,
  }) async {
    openRouter = FakeOpenRouter()..keyOk = keyOk;
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
          openRouterServiceProvider.overrideWithValue(openRouter),
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

  testWidgets('header stays put; the list runs to the bottom edge', (
    tester,
  ) async {
    await open(tester);
    final fade = tester.widget<EdgeFadeScroll>(find.byType(EdgeFadeScroll));
    expect(fade.top, EdgeFadeSide.standard);
    expect(fade.bottom, EdgeFadeSide.none);
    expect(
      find.descendant(
        of: find.byType(EdgeFadeScroll),
        matching: find.text('Pengaturan'),
      ),
      findsNothing,
    );
  });

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

  group('key status', () {
    const keychain =
        'Disimpen di Keychain iPhone, gak dikirim ke mana-mana selain '
        'OpenRouter.';

    testWidgets('a key OpenRouter accepts: "Key-nya jalan"', (tester) async {
      await open(tester);
      expect(find.text('Key-nya jalan'), findsOneWidget);
      expect(find.text('Disimpen di Keychain'), findsOneWidget);
      expect(openRouter.checked, ['sk-or-v1-saved']);
    });

    testWidgets('a rejected key says so', (tester) async {
      await open(tester, keyOk: false);
      expect(find.text('Key-nya ditolak OpenRouter'), findsOneWidget);
    });

    testWidgets('offline: just where it is kept', (tester) async {
      await open(tester, keyOk: null);
      expect(find.text(keychain), findsOneWidget);
      expect(find.text('Key-nya jalan'), findsNothing);
    });

    testWidgets('typing checks once, after a pause', (tester) async {
      await open(tester);
      openRouter.checked.clear();
      for (final k in ['sk-1', 'sk-12', 'sk-123']) {
        await tester.enterText(find.byType(TextField), k);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(openRouter.checked, isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(openRouter.checked, ['sk-123']);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text(keychain), findsOneWidget); // no key, no check
    });
  });
}
