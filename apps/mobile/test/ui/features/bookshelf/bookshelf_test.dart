import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/book_repository.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/data/services/backup_service.dart';
import 'package:luma/domain/models/backup.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/data/repositories/reading_progress_repository.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/features/bookshelf/views/bookshelf_view.dart';
import 'package:luma/ui/features/import_book/view_models/import_view_model.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/ui/core/widgets/book_card.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/core/widgets/book_row.dart';
import 'package:luma/ui/features/bookshelf/views/shelf_header.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/bookshelf/views/book_info_sheet.dart';
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

/// Info + delete without a database or files.
class FakeBooks extends Fake implements BookRepository {
  BookInfo? info;
  final deleted = <int>[];

  @override
  Future<BookInfo?> bookInfo(int id, FileStorage files) async => info;

  @override
  Future<void> delete(int id, FileStorage files) async => deleted.add(id);
}

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
  late FakeBooks repo;
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
    ShelfView view = ShelfView.grid,
    double width = 900,
  }) async {
    settings = FakeSettings()
      ..shelfView = view
      ..lastBackup = neverBackedUp
          ? null
          : lastBackup ?? (at: DateTime.now(), name: 'x.zip', size: 1);
    backup = StuckBackup();
    repo = FakeBooks();
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          backupServiceProvider.overrideWithValue(backup),
          bookRepositoryProvider.overrideWithValue(repo),
          fileStorageProvider.overrideWithValue(
            FileStorage(Directory.systemTemp),
          ),
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
    await tester.pump(); // sort + view come from settings, one frame later
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
    await tester.pump(); // empty → shelf swaps one frame later

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

  group('sort', () {
    final books = [
      book(1, 'Zeta', opened: true, created: DateTime(2026, 10, 1)),
      book(2, 'alpha', opened: true, created: DateTime(2026, 10, 3)),
      book(3, 'Mid', created: DateTime(2026, 10, 2)),
    ];
    List<String> tiles(WidgetTester tester) => tester
        .widgetList<BookCard>(find.byType(BookCard))
        .map((c) => c.title)
        .toList();

    testWidgets('default is last opened; the menu re-sorts and remembers', (
      tester,
    ) async {
      await pump(tester, books);
      expect(tiles(tester), ['Zeta', 'alpha', 'Mid']);

      await tester.tap(find.text('Terakhir dibuka'));
      await tester.pumpAndSettle();
      expect(find.text('Urutin pake'), findsOneWidget);
      await tester.tap(find.text('Judul (A–Z)'));
      await tester.pumpAndSettle();
      expect(tiles(tester), ['alpha', 'Mid', 'Zeta']);
      expect(settings.shelfSort, ShelfSort.title);

      await tester.tap(find.text('Judul (A–Z)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Baru ditambah'));
      await tester.pumpAndSettle();
      expect(tiles(tester), ['alpha', 'Mid', 'Zeta']); // 3rd, 2nd, 1st Oct
      expect(find.text('Baru ditambah'), findsOneWidget);
    });

    testWidgets('the continue card ignores the sort', (tester) async {
      await pump(tester, books);
      await tester.tap(find.text('Terakhir dibuka'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Judul (A–Z)'));
      await tester.pumpAndSettle();
      // Zeta was opened last: still the card, though it sorts to the end.
      final card = find.ancestor(
        of: find.text('Lanjut baca yuk →'),
        matching: find.byType(Semantics),
      );
      expect(
        find.descendant(of: card.first, matching: find.text('Zeta')),
        findsOneWidget,
      );
    });
  });

  group('book menu, info and delete', () {
    final walden = book(
      1,
      'Walden',
      opened: true,
      progress: 0.5,
      chapter: 2,
      chapterCount: 5,
    );
    final info = BookInfo(
      lastOpenedAt: DateTime.now().subtract(const Duration(days: 1)),
      createdAt: DateTime(2026, 9, 12),
      fileName: 'walden.epub',
      fileBytes: 884 * 1024,
      translated: 37,
    );

    Future<void> openMenu(WidgetTester tester) async {
      await tester.longPress(find.byType(BookCard));
      await tester.pumpAndSettle();
    }

    testWidgets('long press: Info buku and Hapus dari rak', (tester) async {
      await pump(tester, [walden]);
      await openMenu(tester);
      expect(find.text('Info buku'), findsOneWidget);
      expect(find.text('Hapus dari rak'), findsOneWidget);
    });

    testWidgets('info sheet lists the details', (tester) async {
      await pump(tester, [walden]);
      repo.info = info;
      await openMenu(tester);
      await tester.tap(find.text('Info buku'));
      await tester.pumpAndSettle();
      for (final text in [
        'Bab 2 dari 5',
        'Kemarin, ${info.lastOpenedAt!.hour.toString().padLeft(2, '0')}'
            '.${info.lastOpenedAt!.minute.toString().padLeft(2, '0')}',
        '12 Sep 2026',
        '37',
        '884 KB',
        'walden.epub',
        'Lanjut baca',
      ]) {
        // The continue card behind the sheet repeats some of it.
        expect(
          find.descendant(
            of: find.byType(BookInfoSheet),
            matching: find.text(text),
          ),
          findsOneWidget,
          reason: text,
        );
      }
    });

    testWidgets('info sheet: Lanjut baca opens the reader', (tester) async {
      await pump(tester, [walden]);
      await openMenu(tester);
      await tester.tap(find.text('Info buku'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut baca'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderView), findsOneWidget);
    });

    testWidgets('delete: confirm says what goes, then deletes', (tester) async {
      await pump(tester, [walden]);
      repo.info = info;
      await openMenu(tester);
      await tester.tap(find.text('Hapus dari rak'));
      await tester.pumpAndSettle();
      expect(find.text('Hapus "Walden" dari rak?'), findsOneWidget);
      expect(
        find.text(
          'Progres 50% sama 37 paragraf yang udah diartiin ikut kehapus. '
          'File aslinya di Files tetep aman kok.',
        ),
        findsOneWidget,
      );
      expect(repo.deleted, isEmpty);
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();
      expect(repo.deleted, [1]);
    });

    testWidgets('delete from the info sheet; Gak jadi keeps the book', (
      tester,
    ) async {
      await pump(tester, [walden]);
      await openMenu(tester);
      await tester.tap(find.text('Info buku'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus dari rak'));
      await tester.pumpAndSettle();
      expect(find.text('Hapus "Walden" dari rak?'), findsOneWidget);
      await tester.tap(find.text('Gak jadi'));
      await tester.pumpAndSettle();
      expect(repo.deleted, isEmpty);
    });

    testWidgets('a never-opened book has nothing to lose but the file', (
      tester,
    ) async {
      await pump(tester, [book(2, 'Emma')]);
      repo.info = BookInfo(
        lastOpenedAt: null,
        createdAt: DateTime(2026, 9, 12),
        fileName: 'emma.epub',
        fileBytes: 1,
        translated: 0,
      );
      await openMenu(tester);
      await tester.tap(find.text('Hapus dari rak'));
      await tester.pumpAndSettle();
      expect(
        find.text('File aslinya di Files tetep aman kok.'),
        findsOneWidget,
      );
    });
  });

  group('grid / list', () {
    final books = [
      book(1, 'Walden', opened: true, progress: 0.489),
      book(2, 'Emma'),
      book(3, 'Dracula', opened: true, progress: 1, finished: true),
    ];

    testWidgets('grid by default; the toggle switches and remembers', (
      tester,
    ) async {
      await pump(tester, books);
      expect(find.byType(BookCard), findsNWidgets(3));
      expect(find.byType(BookRow), findsNothing);

      await tester.tap(find.bySemanticsLabel('Tampilan list'));
      await tester.pumpAndSettle();
      expect(find.byType(BookRow), findsNWidgets(3));
      expect(find.byType(BookCard), findsNothing);
      expect(settings.shelfView, ShelfView.list);

      await tester.tap(find.bySemanticsLabel('Tampilan grid'));
      await tester.pumpAndSettle();
      expect(find.byType(BookCard), findsNWidgets(3));
      expect(settings.shelfView, ShelfView.grid);
    });

    testWidgets('a saved list choice is there on open', (tester) async {
      await pump(tester, books, view: ShelfView.list);
      expect(find.byType(BookRow), findsNWidgets(3));
    });

    for (final b in Brightness.values) {
      testWidgets('list rows: progress, Baru, Kelar! ($b)', (tester) async {
        await pump(tester, books, view: ShelfView.list, brightness: b);
        expect(
          tester.getSize(find.byType(BookRow).first).height,
          Layout.rowHeight,
        );
        final rows = find.byType(BookRow);
        Finder inRow(int i, String text) =>
            find.descendant(of: rows.at(i), matching: find.text(text));
        expect(inRow(0, '48%'), findsOneWidget);
        expect(inRow(1, 'Baru'), findsOneWidget);
        expect(inRow(2, 'Kelar!'), findsOneWidget);
        expect(inRow(0, 'Walden'), findsOneWidget);
        expect(inRow(0, 'Somebody'), findsOneWidget); // the mini cover has none
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('list: tap opens, long press opens the menu', (tester) async {
      await pump(tester, books, view: ShelfView.list);
      await tester.longPress(find.byType(BookRow).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Info buku'), findsOneWidget);
    });

    testWidgets('an import in progress is a row too', (tester) async {
      await pump(tester, books, view: ShelfView.list);
      final context = tester.element(find.byType(BookshelfView));
      final container = ProviderScope.containerOf(context);
      container
          .read(importControllerProvider.notifier)
          .state = const ImportProcessing(
        fileName: 'the-republic.epub',
        size: 1,
        stage: ImportStage.reading,
      );
      await tester.pump();
      expect(find.text('the-republic.epub'), findsWidgets);
      expect(find.text('Lagi diproses'), findsWidgets);
    });

    testWidgets('the shelf ends with a count', (tester) async {
      await pump(tester, books);
      await tester.scrollUntilVisible(
        find.text('Udah mentok. 3 buku di rak lo.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Udah mentok. 3 buku di rak lo.'), findsOneWidget);
    });
  });

  group('header', () {
    final many = [
      for (var i = 1; i <= 40; i++)
        book(i, 'Book $i', opened: i == 1, progress: 0.1, chapter: 1),
    ];
    final header = find.byType(ShelfHeader);

    testWidgets('shrinks from 60 to a 44 bar over 52pt of scroll', (
      tester,
    ) async {
      await pump(tester, many, width: 390);
      expect(tester.getSize(header).height, 60);
      final title = find.text('Rak buku lo');
      final bigTitle = tester.getSize(title).height;

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(26);
      await tester.pump();
      expect(tester.getSize(header).height, 52); // half way: 60 → 44

      position.jumpTo(300);
      await tester.pumpAndSettle();
      expect(tester.getSize(header).height, 44);
      expect(tester.getSize(title).height, lessThan(bigTitle));
      // "Semua buku" stays pinned right under the bar.
      expect(
        tester.getTopLeft(find.text('Semua buku')).dy,
        lessThan(tester.getBottomLeft(header).dy + 44),
      );
      expect(find.text('Semua buku'), findsOneWidget);
    });

    testWidgets('collapsed buttons are drawn 40 but still tap at 44', (
      tester,
    ) async {
      await pump(tester, many, width: 390);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      final gear = find.bySemanticsLabel('Pengaturan app');
      expect(tester.getSize(find.byType(CircleButton).last).width, 40);
      // 21pt from the centre is outside the 40 circle, inside the 44 area.
      await tester.tapAt(tester.getCenter(gear) + const Offset(21, 0));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsView), findsOneWidget);
    });

    testWidgets('big text on a narrow phone: buttons stay, no overflow', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, many, width: 375);
      expect(find.bySemanticsLabel('Import EPUB'), findsOneWidget);
      expect(find.bySemanticsLabel('Pengaturan app'), findsOneWidget);
      expect(find.text('Rak buku lo'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
