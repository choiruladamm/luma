import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/data/repositories/ai_results_repository.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/ai_key_service.dart';
import 'package:luma/data/services/auth_service.dart';
import 'package:luma/data/services/catalog_sync_service.dart';
import 'package:luma/domain/models/ai_model.dart';
import 'package:luma/domain/models/backup.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/routing/router.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/auth/view_models/auth_view_model.dart';
import 'package:luma/ui/features/settings/view_models/ai_quota_view_model.dart';
import 'package:luma/ui/features/settings/views/settings_hub_view.dart';

class _Auth extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState(
    AuthStatus.signedIn,
    user: AuthUser(id: 'u1', name: 'Rara Putri', email: 'rara.putri@gmail.com'),
  );
}

class _Sync extends CatalogSyncController {
  _Sync(this.initial);
  final CatalogSyncState initial;

  @override
  CatalogSyncState build() => initial;
}

class _Quota extends AiQuotaController {
  @override
  Future<QuotaState> build() async => QuotaState(
    usage: AiUsage(
      usedTodayUsd: 0.36,
      dailyLimitUsd: 1,
      remainingUsd: 0.64,
      resetsAt: DateTime.utc(2030, 1, 2),
    ),
  );

  @override
  Future<void> refresh({bool force = false}) async {}
}

void main() {
  final at = DateTime.now().subtract(const Duration(days: 1));

  Future<List<String>> pump(
    WidgetTester tester, {
    LastBackup? backup,
    CatalogSyncState sync = const CatalogSyncIdle(),
    int catalogCount = 100,
    AiCacheStats cache = (paragraphs: 0, bytes: 0),
    String locale = 'id',
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pushed = <String>[];
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SettingsHubView()),
        for (final r in [
          Routes.settingsAccount,
          Routes.settingsAi,
          Routes.settingsBackup,
          Routes.settingsCatalog,
        ])
          GoRoute(
            path: r,
            builder: (_, _) {
              pushed.add(r);
              return const Scaffold();
            },
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          aiQuotaProvider.overrideWith(_Quota.new),
          aiSourceProvider.overrideWith((_) async => AiSource.subsidy),
          aiModelProvider.overrideWith((_) => Stream.value(defaultAiModel)),
          lastBackupProvider.overrideWith((_) => Stream.value(backup)),
          cloudBackupAtProvider.overrideWith((_) => Stream.value(null)),
          appLocaleProvider.overrideWith((_) => Stream.value('en')),
          catalogStatsProvider.overrideWith(
            (_) => Stream.value((
              count: catalogCount,
              syncedAt: null,
              lastModified: null,
            )),
          ),
          catalogSyncProvider.overrideWith(() => _Sync(sync)),
          aiCacheStatsProvider.overrideWith((_) => Stream.value(cache)),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale(locale),
          theme: stabiloTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return pushed;
  }

  final dot = find.byKey(const ValueKey('attention-dot'));

  testWidgets('fits one screen with account, model and 4 tiles', (
    tester,
  ) async {
    await pump(tester, backup: (at: at, name: 'x.luma', size: 1));

    expect(find.text('Rara Putri'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('GLM 5.3 Flash'), findsOneWidget);
    expect(find.text('Ganti model'), findsOneWidget);
    expect(find.text('Atur AI'), findsOneWidget);
    for (final t in ['Backup', 'Katalog', 'Cache', 'Tampilan']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(dot, findsNothing);
  });

  testWidgets('backup never: pink dot + "Belum pernah"', (tester) async {
    await pump(tester);
    expect(find.text('Belum pernah'), findsOneWidget);
    expect(dot, findsOneWidget);
  });

  for (final (name, count, sync, text) in [
    ('not downloaded', 0, const CatalogSyncIdle(), 'Belum diunduh'),
    ('downloading', 100, const CatalogSyncDownloading(0.42), 'Diunduh 42%'),
    ('done', 100, const CatalogSyncIdle(), 'Udah diunduh'),
    ('failed', 100, const CatalogSyncFailed('x'), 'Gagal, coba lagi'),
  ]) {
    testWidgets('catalog $name', (tester) async {
      await pump(tester, catalogCount: count, sync: sync);
      expect(find.text(text), findsOneWidget);
    });
  }

  testWidgets('cache empty and display status', (tester) async {
    await pump(tester);
    expect(find.text('Kosong'), findsOneWidget);
    expect(find.text('Ikut sistem · EN'), findsOneWidget);
  });

  testWidgets('cache used shows size', (tester) async {
    await pump(tester, cache: (paragraphs: 3, bytes: 2936012));
    expect(find.text('2,8 MB terpakai'), findsOneWidget);
  });

  for (final (label, route) in [
    ('Rara Putri', Routes.settingsAccount),
    ('Atur AI', Routes.settingsAi),
    ('Backup', Routes.settingsBackup),
    ('Katalog', Routes.settingsCatalog),
  ]) {
    testWidgets('tap $label opens $route', (tester) async {
      final pushed = await pump(tester);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(pushed, [route]);
    });
  }
}
