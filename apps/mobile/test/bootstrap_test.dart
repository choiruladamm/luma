import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';

import 'fakes.dart';

class UnreadableLocale extends FakeSettings {
  @override
  Stream<String> watchLocale() =>
      Stream.error(StateError('unreadable preference'));
}

void main() {
  testWidgets('unreadable language preference falls back to Indonesian', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(UnreadableLocale()),
          booksStreamProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const LumaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rak buku lo'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('id'),
    );
  });

  testWidgets('saved English loads before content and switch preserves route', (
    tester,
  ) async {
    final settings = FakeSettings()..language = 'en';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          booksStreamProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const LumaApp(),
      ),
    );
    expect(find.text('Rak buku lo'), findsNothing);
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('en'));
    final router = app.routerConfig;
    await settings.saveLocale('id');
    await tester.pumpAndSettle();
    final updated = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(updated.locale, const Locale('id'));
    expect(identical(updated.routerConfig, router), isTrue);
  });

  testWidgets('app boots into the bookshelf', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // Widget tests never touch Drift streams (fake clock → hang).
        overrides: [
          settingsRepositoryProvider.overrideWithValue(FakeSettings()),
          booksStreamProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const LumaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rak buku lo'), findsOneWidget);
  });
}
