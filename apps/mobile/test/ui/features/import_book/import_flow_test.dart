import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/data/services/epub_parser.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/core/widgets/book_card.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/import_book/view_models/import_view_model.dart';

import '../../../fakes.dart';

/// Drives the flow by hand: no picker, no Drift, no isolates.
class FakeImport extends ImportController {
  int picks = 0, cancels = 0;
  @override
  ImportState build() => const ImportIdle();
  void emit(ImportState s) => state = s;
  @override
  Future<void> pick() async => picks++;
  @override
  void cancel() {
    cancels++;
    super.cancel();
  }
}

final walden = ShelfBook(
  id: 7,
  title: 'Walden',
  author: 'Henry David Thoreau',
  coverName: null,
  opened: false,
  createdAt: DateTime(2026, 9, 20),
);

ImportProcessing processing(ImportStage stage, [double progress = 0]) =>
    ImportProcessing(
      fileName: 'walden.epub',
      size: 1258291,
      stage: stage,
      progress: progress,
    );

String _percentText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .firstWhere((t) => t.endsWith('%'));

void main() {
  late FakeImport import;

  Future<void> pump(
    WidgetTester tester, {
    Brightness b = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = b;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    import = FakeImport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(FakeSettings()),
          booksStreamProvider.overrideWith((ref) => Stream.value([])),
          importControllerProvider.overrideWith(() => import),
        ],
        child: const LumaApp(),
      ),
    );
    await tester.pump();
  }

  // Not pumpAndSettle: the pulsing dot in the progress sheet never settles.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> emit(WidgetTester tester, ImportState s) async {
    import.emit(s);
    await settle(tester);
  }

  testWidgets('Import buttons start the picker', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Import EPUB')); // big empty-shelf button
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CircleButton && w.semanticLabel == 'Import EPUB',
      ),
    );
    expect(import.picks, 2);
  });

  for (final b in Brightness.values) {
    testWidgets('processing: sheet with steps + "Lagi diproses" card ($b)', (
      tester,
    ) async {
      await pump(tester, b: b);
      await emit(tester, processing(ImportStage.reading, 0.1));
      expect(find.text('Lagi ngebongkar EPUB...'), findsOneWidget);
      expect(find.text('walden.epub · 1,2 MB'), findsOneWidget);
      expect(find.text('10%'), findsOneWidget);
      expect(find.byType(BookCard), findsOneWidget); // importing card
      expect(find.text('Lagi diproses'), findsOneWidget);

      await emit(tester, processing(ImportStage.chapters, 0.7));
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('Lagi ngebongkar EPUB...'), findsOneWidget); // one sheet
      // Board 13: dua langkah selesai = lingkaran 22 berisi centang 12, di tengah.
      final checks = find.byWidgetPredicate(
        (w) => w is AppIcon && w.icon == AppIcons.check,
      );
      expect(checks, findsNWidgets(2));
      for (final i in [0, 1]) {
        final icon = checks.at(i);
        final circle = find
            .ancestor(of: icon, matching: find.byType(DecoratedBox))
            .first;
        expect(tester.getSize(icon), const Size.square(12));
        expect(tester.getSize(circle), const Size.square(22));
        expect(tester.getCenter(icon), tester.getCenter(circle));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('percent + bar glide to the new value, never jump', (
    tester,
  ) async {
    await pump(tester);
    await emit(tester, processing(ImportStage.chapters, 0.2));
    expect(find.text('20%'), findsOneWidget);

    import.emit(processing(ImportStage.chapters, 0.8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75)); // halfway
    final mid = int.parse(
      RegExp(r'(\d+)%').firstMatch(_percentText(tester))!.group(1)!,
    );
    expect(mid, inExclusiveRange(20, 80));
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, inExclusiveRange(0.2, 0.8));

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('80%'), findsOneWidget);
  });

  testWidgets('reduce motion: percent shows, value jumps without gliding', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pump(tester);
    await emit(tester, processing(ImportStage.chapters, 0.2));
    import.emit(processing(ImportStage.chapters, 0.8));
    await tester.pump();
    await tester.pump();
    expect(find.text('80%'), findsOneWidget);
  });

  testWidgets('Batalin cancels and closes the sheet', (tester) async {
    await pump(tester);
    await emit(tester, processing(ImportStage.outline));
    await tester.tap(find.text('Batalin'));
    await settle(tester);
    expect(import.cancels, 1);
    expect(find.text('Lagi ngebongkar EPUB...'), findsNothing);
    expect(find.byType(BookCard), findsNothing);
  });

  testWidgets('success: progress sheet closes, toast offers Baca', (
    tester,
  ) async {
    await pump(tester);
    await emit(tester, processing(ImportStage.saving));
    await emit(tester, ImportSuccess(walden));
    expect(find.text('Lagi ngebongkar EPUB...'), findsNothing);
    expect(find.text('Sip, udah masuk rak!'), findsOneWidget);
    expect(find.text('Walden · Henry David Thoreau'), findsOneWidget);
    expect(find.text('Baca'), findsOneWidget);
    expect(import.state, isA<ImportIdle>());
  });

  testWidgets('duplicate: sheet with the existing book', (tester) async {
    await pump(tester);
    await emit(tester, processing(ImportStage.reading));
    await emit(tester, ImportDuplicate(walden));
    expect(find.text('Eh, buku ini udah ada di rak'), findsOneWidget);
    expect(find.text('Buka yang udah ada'), findsOneWidget);
    expect(
      find.textContaining('Henry David Thoreau · ditambah'),
      findsOneWidget,
    );

    await tester.tap(find.text('Ganti file-nya'));
    await settle(tester);
    expect(import.picks, 1);
    expect(find.text('Eh, buku ini udah ada di rak'), findsNothing);
  });

  for (final (error, title, code) in [
    (EpubError.corrupt, 'File-nya rusak nih', 'walden.epub · file rusak'),
    (EpubError.notEpub, 'Ini bukan EPUB', 'walden.epub'),
    (EpubError.drm, 'Bukunya dikunci DRM', 'walden.epub · DRM'),
  ]) {
    testWidgets('failed: $error', (tester) async {
      await pump(tester, b: Brightness.dark);
      await emit(tester, processing(ImportStage.outline));
      await emit(tester, ImportFailed(fileName: 'walden.epub', error: error));
      expect(find.text(title), findsOneWidget);
      expect(find.text(code), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Tutup').last);
      await settle(tester);
      expect(find.text(title), findsNothing);
      expect(import.state, isA<ImportIdle>());
    });
  }
}
