import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/backup_service.dart';
import 'package:luma/domain/models/backup.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/data/repositories/reading_progress_repository.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/core/widgets/book_card.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/reader/view_models/reader_view_model.dart';
import 'package:luma/ui/features/reader/views/reader_view.dart';
import 'package:luma/ui/features/settings/views/settings_view.dart';

import '../../../fakes.dart';

ShelfBook book(
  int id,
  String title, {
  bool opened = false,
  DateTime? created,
  double progress = 0,
  bool finished = false,
  int chapter = 1,
  int chapterCount = 1,
}) => ShelfBook(
  id: id,
  title: title,
  author: 'Somebody',
  coverName: null,
  opened: opened,
  createdAt: created ?? DateTime(2026, 10, 1),
  progress: progress,
  finished: finished,
  chapter: chapter,
  chapterCount: chapterCount,
);

/// Backup that never finishes: keeps the progress sheet up.
class StuckBackup extends Fake implements BackupService {
  bool started = false;

  @override
  Future<BackupFile?> export({
    DateTime? now,
    void Function(String name, BackupManifest manifest)? onStart,
    void Function(BackupStage stage, double fraction)? onProgress,
    Future<void>? cancel,
  }) {
    started = true;
    return Completer<BackupFile?>().future;
  }
}

void main() {
  // The shelf is fed by a controller, not Drift: widget tests run on a fake
  // clock and Drift streams need the real one (they hang). The Drift side is
  // covered in test/data/book_repository_test.dart.
  late StreamController<List<ShelfBook>> shelf;
  late FakeSettings settings;
  late StuckBackup backup;
  setUp(() => shelf = StreamController());
  // Fire-and-forget: close() waits for the listener (the app's provider)
  // to go away, which never happens if a test fails mid-way, and an awaited
  // tearDown then hangs the whole run past --timeout.
  tearDown(() => unawaited(shelf.close()));

  Future<void> pump(
    WidgetTester tester,
    List<ShelfBook> books, {
    Brightness brightness = Brightness.light,
    // Fresh backup by default: no reminder unless a test wants one.
    LastBackup? lastBackup,
    bool neverBackedUp = false,
  }) async {
    settings = FakeSettings()
      ..lastBackup = neverBackedUp
          ? null
          : lastBackup ?? (at: DateTime.now(), name: 'x.zip', size: 1);
    backup = StuckBackup();
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          backupServiceProvider.overrideWithValue(backup),
          booksStreamProvider.overrideWith((ref) => shelf.stream),
          // Opening a book shows the reader: feed it too, never the real DB.
          readerBookProvider.overrideWith((ref, id) async => null),
          readingProgressRepositoryProvider.overrideWithValue(FakeProgress()),
        ],
        child: const LumaApp(),
      ),
    );
    shelf.add(books);
    await tester.pump();
  }

  for (final b in Brightness.values) {
    testWidgets('empty shelf invites an import ($b)', (tester) async {
      await pump(tester, [], brightness: b);
      expect(find.text('Rak buku lo'), findsOneWidget);
      expect(find.text('Import EPUB'), findsOneWidget);
      expect(
        find.text('Ambil dari app Files, format .epub aja'),
        findsOneWidget,
      );
      expect(find.byType(BookCard), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a new book shows up as soon as the shelf stream emits', (
    tester,
  ) async {
    await pump(tester, []);
    shelf.add([
      book(2, 'The Enchiridion', opened: true),
      book(1, 'Meditations'),
    ]);
    await tester.pump();

    expect(find.text('Semua buku'), findsOneWidget);
    expect(
      tester.widgetList<BookCard>(find.byType(BookCard)).map((c) => c.title),
      ['The Enchiridion', 'Meditations'],
    );
    expect(find.text('Baru'), findsOneWidget); // only the unopened one
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a book opens the reader; the gear opens settings', (
    tester,
  ) async {
    await pump(tester, [book(1, 'Meditations')]);

    await tester.tap(find.byType(BookCard));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderView), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Balik ke rak'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Pengaturan app'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsOneWidget);
  });

  group('continue card', () {
    for (final b in Brightness.values) {
      testWidgets('last opened book: chapter and percent ($b)', (tester) async {
        await pump(tester, [
          book(
            2,
            'Walden',
            opened: true,
            progress: 0.489,
            chapter: 3,
            chapterCount: 12,
          ),
          book(1, 'Meditations'),
        ], brightness: b);
        expect(find.text('Lanjut baca yuk →'), findsOneWidget);
        expect(find.text('Bab 3 dari 12'), findsOneWidget);
        // Card + tile: same rounding as the sticker.
        expect(find.text('48%'), findsNWidgets(2));
        expect(find.text('Walden'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('tapping it opens the reader', (tester) async {
      await pump(tester, [book(2, 'Walden', opened: true, progress: 0.2)]);
      await tester.tap(find.text('Lanjut baca yuk →'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderView), findsOneWidget);
    });

    testWidgets('no card when the first book was never opened', (tester) async {
      await pump(tester, [book(1, 'Meditations')]);
      expect(find.text('Lanjut baca yuk →'), findsNothing);
    });

    testWidgets('no card for a finished book; its tile says Kelar!', (
      tester,
    ) async {
      await pump(tester, [
        book(1, 'Walden', opened: true, progress: 1, finished: true),
      ]);
      expect(find.text('Lanjut baca yuk →'), findsNothing);
      expect(find.text('Kelar!'), findsOneWidget);
    });
  });

  group('backup reminder', () {
    DateTime daysAgo(int n) => DateTime.now().subtract(Duration(days: n));

    testWidgets('6 days since the last backup: the banner', (tester) async {
      await pump(
        tester,
        [book(1, 'Walden')],
        lastBackup: (at: daysAgo(6), name: 'x.zip', size: 1),
      );
      expect(find.text('Udah 6 hari belum backup nih'), findsOneWidget);
      expect(
        find.text('Besok jatah install ulang. Amanin data lo dulu yuk.'),
        findsOneWidget,
      );
      expect(find.text('Backup sekarang'), findsOneWidget);
    });

    testWidgets('a recent backup: no banner', (tester) async {
      await pump(
        tester,
        [book(1, 'Walden')],
        lastBackup: (at: daysAgo(2), name: 'x.zip', size: 1),
      );
      expect(find.bySemanticsLabel('Pengingat backup'), findsNothing);
      expect(find.textContaining('belum backup'), findsNothing);
    });

    testWidgets('never backed up: counts from the first book', (tester) async {
      await pump(tester, [
        book(1, 'Walden', created: daysAgo(10)),
      ], neverBackedUp: true);
      expect(find.text('Belum pernah backup nih'), findsOneWidget);
    });

    testWidgets('closing it hides it and remembers today', (tester) async {
      await pump(
        tester,
        [book(1, 'Walden')],
        lastBackup: (at: daysAgo(8), name: 'x.zip', size: 1),
      );
      expect(find.text('Udah 8 hari belum backup nih'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Tutup pengingat'));
      await tester.pumpAndSettle();
      expect(find.textContaining('belum backup'), findsNothing);
      expect(settings.dismissed, isNotNull);
    });

    testWidgets('"Backup sekarang" starts it right on the shelf', (
      tester,
    ) async {
      await pump(
        tester,
        [book(1, 'Walden')],
        lastBackup: (at: daysAgo(9), name: 'x.zip', size: 1),
      );
      await tester.tap(find.text('Backup sekarang'));
      await tester.pumpAndSettle();
      expect(backup.started, isTrue);
      expect(find.text('Lagi ngebungkus backup...'), findsOneWidget);
    });
  });
}
