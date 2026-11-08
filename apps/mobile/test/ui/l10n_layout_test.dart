import 'package:luma/ui/features/reader/views/reader_capsule.dart';
import 'package:luma/ui/features/reader/views/chapter_heading.dart';
import 'package:luma/ui/features/chat/views/chat_composer.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/ai_breakdowns_repository.dart';
import 'package:luma/data/repositories/ai_results_repository.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/api_key_store.dart';
import 'package:luma/data/services/catalog_sync_service.dart';
import 'package:luma/data/services/openrouter_service.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/settings/views/settings_view.dart';

import '../fakes.dart';
import 'features/settings/settings_test.dart' as fixtures;

class MemoryKey extends Fake implements ApiKeyStore {
  @override
  Future<String?> read() async => null;
}

void main() {
  setUpAll(() async {
    for (final family in ['Bricolage Grotesque', 'Atkinson Hyperlegible']) {
      final stem = family.replaceAll(' ', '');
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$stem-400.ttf'));
      await loader.load();
    }
  });

  for (final language in ['id', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'narrow screen, large text: shelf and Settings $language $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final settings = FakeSettings()..language = language;
          final cache = fixtures.FakeAiResults();
          addTearDown(() => unawaited(cache.stats.close()));
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                settingsRepositoryProvider.overrideWithValue(settings),
                booksStreamProvider.overrideWith((ref) => Stream.value([])),
              ],
              child: const LumaApp(),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.text(language == 'id' ? 'Rak buku lo' : 'Your bookshelf'),
            findsOneWidget,
          );
          await tester.pumpWidget(
            ProviderScope(
              key: const ValueKey('settings'),
              overrides: [
                settingsRepositoryProvider.overrideWithValue(settings),
                apiKeyStoreProvider.overrideWithValue(MemoryKey()),
                openRouterServiceProvider.overrideWithValue(FakeOpenRouter()),
                aiResultsRepositoryProvider.overrideWithValue(cache),
                aiBreakdownsRepositoryProvider.overrideWithValue(
                  fixtures.FakeBreakdowns(),
                ),
                catalogSyncProvider.overrideWith(
                  () => fixtures.FakeCatalogSync(const CatalogSyncIdle()),
                ),
                catalogStatsProvider.overrideWith(
                  (ref) => Stream.value((
                    count: 0,
                    syncedAt: null,
                    lastModified: null,
                  )),
                ),
              ],
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: Locale(language),
                theme: stabiloTheme(brightness),
                home: const SettingsView(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.text(
              language == 'id' ? 'Bahasa antarmuka' : 'Interface language',
            ),
            findsOneWidget,
          );
          final list = find.byType(Scrollable).first;
          for (var i = 0; i < 5; i++) {
            await tester.drag(list, const Offset(0, -400));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale(language),
              theme: stabiloTheme(brightness),
              home: Scaffold(
                body: ListView(
                  children: [
                    ReaderTopCapsule(
                      title: 'A very long original chapter title',
                      onBack: () {},
                      onToc: () {},
                      onMore: () {},
                    ),
                    const ChapterHeading(
                      title: 'A very long original chapter title',
                      number: 2,
                      total: 100,
                      minutes: 14,
                      reading: TextStyle(
                        fontFamily: 'Atkinson Hyperlegible',
                        fontSize: 20,
                      ),
                    ),
                    ChatComposer(
                      draft: 'Pertanyaan asli user',
                      canSend: true,
                      running: false,
                      enabled: true,
                      onChanged: (_) {},
                      onSend: () {},
                      onStop: () {},
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Pertanyaan asli user'), findsOneWidget);
          expect(
            find.bySemanticsLabel(
              language == 'id' ? 'Kirim pertanyaan' : 'Send question',
            ),
            findsOneWidget,
          );
        },
      );
    }
  }
}
