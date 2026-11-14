import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/data/services/catalog_sync_service.dart';
import 'package:luma/l10n/app_localizations.dart';
import 'package:luma/ui/core/theme/stabilo_theme.dart';
import 'package:luma/ui/features/settings/views/catalog_view.dart';

class _FakeSync extends CatalogSyncController {
  _FakeSync(this.initial);

  final CatalogSyncState initial;
  static int syncs = 0;
  static int cancels = 0;

  @override
  CatalogSyncState build() => initial;

  @override
  Future<void> sync({bool force = false}) async => syncs++;

  @override
  void cancel() => cancels++;

  void emit(CatalogSyncState s) => state = s;
}

void main() {
  Future<void> open(
    WidgetTester tester, {
    Brightness b = Brightness.light,
    CatalogSyncState sync = const CatalogSyncIdle(),
    CatalogStats? stats = (count: 61900, syncedAt: null, lastModified: null),
    bool settle = true,
  }) async {
    _FakeSync.syncs = 0;
    _FakeSync.cancels = 0;
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogSyncProvider.overrideWith(() => _FakeSync(sync)),
          catalogStatsProvider.overrideWith(
            (ref) => stats == null ? const Stream.empty() : Stream.value(stats),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          theme: stabiloTheme(b),
          home: const CatalogView(),
        ),
      ),
    );
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
  }

  for (final b in Brightness.values) {
    testWidgets('never downloaded: Unduh syncs (${b.name})', (tester) async {
      await open(
        tester,
        b: b,
        stats: (count: 0, syncedAt: null, lastModified: null),
      );
      expect(find.text('Katalog buku'), findsOneWidget);
      expect(find.text('Belum diunduh · 5,6 MB'), findsOneWidget);
      expect(find.text('Buat apa?'), findsOneWidget);
      await tester.tap(find.text('Unduh'));
      expect(_FakeSync.syncs, 1);
    });
  }

  testWidgets('downloaded: date + count, Perbarui syncs', (tester) async {
    await open(
      tester,
      stats: (
        count: 61900,
        syncedAt: DateTime(2026, 10, 25),
        lastModified: 'x',
      ),
    );
    expect(find.text('61.900 buku · Diperbarui 25 Okt 2026'), findsOneWidget);
    await tester.tap(find.text('Perbarui'));
    expect(_FakeSync.syncs, 1);
  });

  testWidgets('stats not loaded: button disabled', (tester) async {
    await open(tester, stats: null);
    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Perbarui'),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('downloading: percent, progress bar, Batal cancels', (
    tester,
  ) async {
    await open(tester, sync: const CatalogSyncDownloading(0.42));
    expect(find.text('Lagi diunduh'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.42,
    );
    expect(find.textContaining('unduhan jalan terus'), findsOneWidget);
    await tester.tap(find.text('Batal'));
    expect(_FakeSync.cancels, 1);
  });

  testWidgets('downloading without a length: no percent', (tester) async {
    await open(tester, sync: const CatalogSyncDownloading(-1), settle: false);
    expect(find.text('Lagi diunduh'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('importing: spinner, no button', (tester) async {
    await open(tester, sync: const CatalogSyncImporting(), settle: false);
    expect(find.text('Nyusun katalog…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('failed: Coba lagi syncs', (tester) async {
    await open(tester, sync: const CatalogSyncFailed('HTTP 503'));
    expect(find.text('Gagal, katalog lama tetep dipakai'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    expect(_FakeSync.syncs, 1);
  });

  testWidgets('304 shows the up-to-date toast', (tester) async {
    await open(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CatalogView)),
    );
    (container.read(catalogSyncProvider.notifier) as _FakeSync).emit(
      const CatalogSyncUpToDate(),
    );
    await tester.pump();
    expect(find.text('Katalognya udah yang terbaru'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });
}
