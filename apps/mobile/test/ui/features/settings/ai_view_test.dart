import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/ai_key_service.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/domain/models/ai_model.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/settings/view_models/ai_quota_view_model.dart';
import 'package:luma/ui/features/settings/view_models/settings_view_model.dart';
import 'package:luma/ui/features/settings/views/ai_view.dart';

import '../../../fakes.dart';

class FakeQuota extends AiQuotaController {
  @override
  Future<QuotaState> build() async => QuotaState(
    usage: AiUsage(
      dailyLimitUsd: 0.02,
      remainingUsd: 0.0128,
      usedTodayUsd: 0.0072,
      resetsAt: DateTime.utc(2026, 11, 14),
    ),
  );

  @override
  Future<void> refresh({bool force = false}) async {}
}

void main() {
  late FakeSettings settings;
  late FakeOpenRouter openRouter;

  Future<void> open(
    WidgetTester tester, {
    Brightness b = Brightness.light,
    bool? keyOk = true,
    Completer<void>? gate,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings = FakeSettings();
    openRouter = FakeOpenRouter()
      ..keyOk = keyOk
      ..gate = gate;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          apiKeyStoreProvider.overrideWithValue(ApiKeyStore()),
          openRouterServiceProvider.overrideWithValue(openRouter),
          aiQuotaProvider.overrideWith(FakeQuota.new),
          subsidyModelsProvider.overrideWith((ref) => subsidyModelIds),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          theme: stabiloTheme(b),
          home: const AiView(),
        ),
      ),
    );
    // Spinner (state checking) never settles: pump a few frames instead.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void noKey() => FlutterSecureStorage.setMockInitialValues({});
  void savedKey() => FlutterSecureStorage.setMockInitialValues({
    'openrouter_api_key': 'sk-or-v1-saved',
  });

  for (final b in Brightness.values) {
    testWidgets('free quota: 3 radio models, hint, no key field ($b)', (
      tester,
    ) async {
      noKey();
      await open(tester, b: b);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('Model AI · 3 model gratis'), findsOneWidget);
      for (final m in aiModels) {
        expect(find.text(m.label), findsOneWidget);
      }
      expect(find.text('Default'), findsOneWidget);
      expect(find.textContaining('300-an model lain'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('key being checked ($b)', (tester) async {
      savedKey();
      await open(tester, b: b, gate: Completer<void>());
      expect(find.text('Lagi ngecek ke OpenRouter…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'sk-or-v1-saved');
      expect(field.obscureText, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('key works ($b)', (tester) async {
      savedKey();
      await open(tester, b: b);
      expect(find.text('Key-nya jalan'), findsOneWidget);
      expect(find.text('Dicek barusan'), findsOneWidget);
      expect(find.text('Balik ke kuota gratis'), findsOneWidget);
      expect(find.textContaining('Biayanya kepotong'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('key rejected: falls back to free quota ($b)', (tester) async {
      savedKey();
      await open(tester, b: b, keyOk: false);
      expect(find.text('Key-nya ditolak (401)'), findsOneWidget);
      expect(find.text('Cek lagi'), findsOneWidget);
      expect(find.textContaining('openrouter.ai/keys'), findsOneWidget);
      expect(
        find.text(
          'Sementara AI balik pakai kuota gratis (sisa 64%) sampai key-nya bener.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('z-ai/glm-5.3-flash · balik ke model gratis'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selecting a free model saves it', (tester) async {
    noKey();
    await open(tester);
    await tester.tap(find.text(aiModels[1].label));
    await tester.pump();
    expect(settings.model, aiModels[1].id);
  });

  testWidgets('Key sendiri tab opens the key field; back to free tab', (
    tester,
  ) async {
    noKey();
    await open(tester);
    await tester.tap(find.text('Key sendiri'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Biayanya kepotong'), findsOneWidget);
    await tester.tap(find.text('Kuota gratis'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a good key is checked, then saved', (tester) async {
    noKey();
    await open(tester);
    await tester.tap(find.text('Key sendiri'));
    await tester.pump();
    const good = 'sk-or-v1-0123456789abcdef';
    await tester.enterText(find.byType(TextField), good);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(openRouter.checked, [good]);
    expect(await ApiKeyStore().read(), good);
    expect(find.text('Key-nya jalan'), findsOneWidget);
  });

  testWidgets('a key OpenRouter refuses is not saved', (tester) async {
    noKey();
    await open(tester, keyOk: false);
    await tester.tap(find.text('Key sendiri'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'sk-or-v1-0123456789abcdef');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.textContaining('gak disimpen'), findsOneWidget);
    expect(find.text('Cek lagi'), findsOneWidget);
    expect(await ApiKeyStore().read(), isNull);
  });

  testWidgets('back to free: confirm wipes the key and resets the model', (
    tester,
  ) async {
    savedKey();
    await open(tester);
    await tester.tap(find.text('Balik ke kuota gratis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Balik ke gratis'));
    await tester.pumpAndSettle();
    expect(await ApiKeyStore().read(), isNull);
    expect(settings.model, defaultAiModel);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Model AI · 3 model gratis'), findsOneWidget);
  });

  group('key input (ported)', () {
    const good = 'sk-or-v1-0123456789abcdef';
    final field = find.byType(TextField);
    const clear = 'Hapus API key OpenRouter';

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(field, text);
      await tester.pump(const Duration(milliseconds: 700)); // debounce
      await tester.pump();
      await tester.pump();
    }

    String shown(WidgetTester tester) =>
        tester.widget<TextField>(field).controller!.text;

    testWidgets('text that is not a key is never saved or sent', (
      tester,
    ) async {
      savedKey();
      await open(tester);
      openRouter.checked.clear();
      await type(tester, 'halo dunia');
      expect(find.textContaining('bukan API key OpenRouter'), findsOneWidget);
      expect(openRouter.checked, isEmpty);
      expect(await ApiKeyStore().read(), 'sk-or-v1-saved');
    });

    testWidgets('offline: a well-formed key is saved anyway', (tester) async {
      savedKey();
      await open(tester);
      openRouter.keyOk = null;
      await type(tester, good);
      expect(await ApiKeyStore().read(), good);
      expect(find.text('Key-nya jalan'), findsNothing);
      expect(find.textContaining('gak disimpen'), findsNothing);
    });

    testWidgets('pasted spaces and new lines never reach the field', (
      tester,
    ) async {
      savedKey();
      await open(tester);
      await type(tester, '  $good \n');
      expect(shown(tester), good);
      expect(await ApiKeyStore().read(), good);
    });

    testWidgets('the clear button wipes the field and the secure storage', (
      tester,
    ) async {
      savedKey();
      await open(tester);
      await tester.tap(find.bySemanticsLabel(clear));
      await tester.pump();
      await tester.pump();
      expect(shown(tester), isEmpty);
      expect(await ApiKeyStore().read(), isNull);
      expect(find.bySemanticsLabel(clear), findsNothing);
    });

    testWidgets('no clear button while the field is empty', (tester) async {
      noKey();
      await open(tester);
      await tester.tap(find.text('Key sendiri'));
      await tester.pump();
      expect(find.bySemanticsLabel(clear), findsNothing);
      await tester.enterText(field, good);
      await tester.pump();
      expect(find.bySemanticsLabel(clear), findsOneWidget);
    });

    testWidgets('emptying the field by hand deletes the key too', (
      tester,
    ) async {
      savedKey();
      await open(tester);
      await tester.enterText(field, '');
      await tester.pump();
      expect(await ApiKeyStore().read(), isNull);
    });

    testWidgets('typing checks once, after a pause', (tester) async {
      savedKey();
      await open(tester);
      openRouter.checked.clear();
      for (final k in [
        'sk-or-v1-aaaaaaa1',
        'sk-or-v1-aaaaaa12',
        'sk-or-v1-aaaaa123',
      ]) {
        await tester.enterText(field, k);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(openRouter.checked, isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(openRouter.checked, ['sk-or-v1-aaaaa123']);
    });

    test(
      'reopening shows the last verdict at once, re-checks quietly',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          'openrouter_api_key': 'sk-or-v1-saved',
        });
        final fake = FakeOpenRouter();
        final container = ProviderContainer(
          overrides: [
            apiKeyStoreProvider.overrideWithValue(ApiKeyStore()),
            openRouterServiceProvider.overrideWithValue(fake),
          ],
        );
        addTearDown(container.dispose);
        final first = container.listen(apiKeyEntryProvider, (_, _) {});
        expect(first.read(), KeyStatus.checking);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(first.read(), KeyStatus.valid);
        first.close();
        await Future<void>.delayed(Duration.zero); // autoDispose

        final gate = Completer<void>();
        fake.gate = gate;
        final again = container.listen(apiKeyEntryProvider, (_, _) {});
        expect(again.read(), KeyStatus.valid); // no "checking" in between
        fake.keyOk = false;
        gate.complete();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(again.read(), KeyStatus.rejected);
      },
    );

    testWidgets('offline: key status does not claim it works', (tester) async {
      savedKey();
      await open(tester, keyOk: null);
      expect(find.text('Key-nya jalan'), findsNothing);
    });
  });
}
