import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/repositories/settings_repository.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/data/services/epub_parser.dart';
import 'package:luma/data/repositories/book_repository.dart';
import 'package:luma/domain/luma_markdown.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/main.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/ui/core/widgets/book_card.dart';
import 'package:luma/ui/core/widgets/buttons.dart';
import 'package:luma/ui/features/bookshelf/view_models/bookshelf_view_model.dart';
import 'package:luma/ui/features/import_book/view_models/import_view_model.dart';

import '../../../fakes.dart';

/// Drives the flow by hand: no picker, no Drift, no isolates.
class FakeImport extends ImportController {
  int picks = 0, cancels = 0, replaces = 0, cancelReplaces = 0;
  final submitted = <MarkdownChoice>[];
  @override
  ImportState build() => const ImportIdle();
  void emit(ImportState s) => state = s;
  @override
  Future<void> submitMarkdown(
    MarkdownChoice choice, {
    bool replace = false,
  }) async => submitted.add(choice);
  @override
  Future<void> confirmReplace() async => replaces++;
  @override
  void cancelReplace() {
    cancelReplaces++;
    super.cancelReplace();
  }

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

  group('markdown', () {
    ShelfBook shelf(int id, String title) => ShelfBook(
      id: id,
      title: title,
      author: null,
      coverName: null,
      opened: false,
      createdAt: DateTime(2026, 9, 20),
    );
    final atomic = (book: shelf(1, 'Atomic Habits'), chapters: [1, 3, 7]);
    final filsafat = (
      book: shelf(2, 'Catatan Kuliah Filsafat'),
      chapters: [1, 2],
    );
    final psikologi = (book: shelf(3, 'Psikologi Uang'), chapters: [5]);
    final sapiens = (book: shelf(4, 'Sapiens (catatan)'), chapters: [2, 4]);

    ImportMarkdownAsk ask({List<MarkdownBook>? books}) => ImportMarkdownAsk(
      fileName: 'bab-1-deep-work.md',
      parsed: parseLumaMarkdown(
        '# Deep Work\n\n## Deep Work Is Valuable\n\nIsi.',
        fileName: 'bab-1-deep-work.md',
      ),
      books: books ?? [atomic, filsafat],
    );

    Finder field(int i) => find.byType(TextField).at(i);
    Finder masukin() => find.widgetWithText(AppButton, 'Masukin');
    bool masukinOn(WidgetTester t) =>
        t.widget<AppButton>(masukin()).onPressed != null;

    testWidgets('sheet: "Buku baru" selected, fields prefilled with guesses', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, ask());
      expect(find.text('Masuk ke buku mana?'), findsOneWidget);
      expect(find.text('bab-1-deep-work.md'), findsOneWidget);
      expect(find.text('Buku baru'), findsOneWidget);
      expect(find.text('Bikin buku dari file ini'), findsOneWidget);
      expect(find.text('Bab 1, 3, 7'), findsOneWidget);
      expect(find.text('Bab 1, 2'), findsOneWidget);
      expect(find.text('Ditebak dari judul di file. Boleh diubah.'), findsOne);
      expect(tester.widget<TextField>(field(0)).controller!.text, 'Deep Work');
      expect(tester.widget<TextField>(field(1)).controller!.text, 'Deep Work');
      expect(tester.widget<TextField>(field(2)).controller!.text, '1');
      expect(masukinOn(tester), isTrue);

      await tester.tap(masukin());
      expect(import.submitted.single, (
        bookId: null,
        bookKey: 'deep-work',
        bookTitle: 'Deep Work',
        author: null,
        chapter: 1,
        chapterTitle: 'Deep Work',
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking a book hides Judul buku, number = last + 1', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, ask());
      await tester.tap(find.text('Atomic Habits'));
      await tester.pump();
      expect(find.text('Judul buku'), findsNothing);
      expect(
        find.text('Ditebak dari judul di file. Boleh diubah.'),
        findsNothing,
      );
      expect(find.text('Bab terakhir di buku ini: 7'), findsOneWidget);
      // File says bab 1 (from the name), which Atomic Habits already has.
      expect(tester.widget<TextField>(field(1)).controller!.text, '1');

      await tester.enterText(field(1), '8');
      await tester.tap(masukin());
      expect(import.submitted.single.bookId, 1);
      expect(import.submitted.single.chapter, 8);
    });

    testWidgets('more than 3 rows: list scrolls inside the sheet', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, ask(books: [atomic, filsafat, psikologi, sapiens]));
      // "Buku baru" + 4 books; rows past the 3 visible ones peek + scroll.
      final list = find.byType(SingleChildScrollView).evaluate().length;
      expect(list, greaterThanOrEqualTo(2)); // sheet body + book list
      await tester.ensureVisible(find.text('Sapiens (catatan)'));
      await tester.tap(find.text('Sapiens (catatan)'));
      await tester.pump();
      expect(find.text('Bab terakhir di buku ini: 4'), findsOneWidget);
    });

    testWidgets('validation: empty book title and non-number chapter', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, ask());
      await tester.enterText(field(0), '');
      await tester.enterText(field(2), 'dua');
      await tester.pump();
      expect(find.text('Judul buku gak boleh kosong'), findsOneWidget);
      expect(find.text('Harus angka'), findsOneWidget);
      expect(masukinOn(tester), isFalse);

      await tester.enterText(field(0), 'Deep Work');
      await tester.enterText(field(2), '2');
      await tester.pump();
      expect(find.text('Judul buku gak boleh kosong'), findsNothing);
      expect(masukinOn(tester), isTrue);
    });

    testWidgets('duplicate chapter: dialog over the sheet, Batal keeps input', (
      tester,
    ) async {
      await pump(tester);
      final a = ask();
      await emit(tester, a);
      await tester.tap(find.text('Atomic Habits'));
      await tester.pump();
      await tester.enterText(field(1), '7');
      await tester.pump();

      await emit(
        tester,
        ImportMarkdownConflict(
          fileName: a.fileName,
          parsed: a.parsed,
          books: a.books,
          choice: (
            bookId: 1,
            bookKey: 'atomic-habits',
            bookTitle: 'Atomic Habits',
            author: null,
            chapter: 7,
            chapterTitle: null,
          ),
          chapter: 7,
        ),
      );
      expect(find.text('Bab 7 udah ada'), findsOneWidget);
      expect(
        find.text(
          'Kalau diganti, terjemahan yang udah kesimpen di bab 7 yang lama '
          'ikut kehapus.',
        ),
        findsOneWidget,
      );

      final dialog = find.byType(Dialog);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Batal')),
      );
      await settle(tester);
      expect(import.cancelReplaces, 1);
      expect(import.state, isA<ImportMarkdownAsk>());
      expect(find.text('Bab 7 udah ada'), findsNothing);
      expect(find.text('Masuk ke buku mana?'), findsOneWidget); // one sheet
      expect(tester.widget<TextField>(field(1)).controller!.text, '7');
      // Batal put the cursor back on Nomor bab.
      expect(tester.widget<TextField>(field(1)).focusNode!.hasFocus, isTrue);

      await emit(
        tester,
        ImportMarkdownConflict(
          fileName: a.fileName,
          parsed: a.parsed,
          books: a.books,
          choice: (
            bookId: 1,
            bookKey: 'atomic-habits',
            bookTitle: 'Atomic Habits',
            author: null,
            chapter: 7,
            chapterTitle: null,
          ),
          chapter: 7,
        ),
      );
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Ganti')),
      );
      await tester.pump();
      expect(import.replaces, 1);
      // Ganti: spinner instead of the label, Batal off, dialog stays.
      expect(
        find.descendant(
          of: dialog,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final batal = find.descendant(
        of: dialog,
        matching: find.widgetWithText(AppButton, 'Batal'),
      );
      expect(tester.widget<AppButton>(batal).onPressed, isNull);

      // Result arrives: sheet + dialog go together, toast follows (5 s).
      await emit(
        tester,
        ImportMarkdownDone(
          book: atomic.book,
          chapter: 7,
          chapterId: 70,
          created: false,
          replaced: true,
        ),
      );
      expect(find.text('Bab 7 udah ada'), findsNothing);
      expect(find.text('Masuk ke buku mana?'), findsNothing);
      expect(find.text('Bab 7 masuk ke Atomic Habits ✨'), findsOneWidget);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        Motion.toastBaca,
      );
    });

    testWidgets('errors show after leaving the field, not before', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, ask());
      tester.widget<TextField>(field(2)).controller!.text = 'dua';
      await tester.pump();
      expect(find.text('Harus angka'), findsNothing);

      await tester.tap(field(2));
      await tester.pump();
      await tester.tap(field(1)); // focus leaves Nomor bab
      await tester.pump();
      expect(find.text('Harus angka'), findsOneWidget);
    });

    testWidgets('failed after Ganti: dialog + sheet close, error sheet opens', (
      tester,
    ) async {
      await pump(tester);
      final a = ask();
      await emit(tester, a);
      await emit(
        tester,
        ImportMarkdownConflict(
          fileName: a.fileName,
          parsed: a.parsed,
          books: a.books,
          choice: (
            bookId: 1,
            bookKey: 'atomic-habits',
            bookTitle: 'Atomic Habits',
            author: null,
            chapter: 7,
            chapterTitle: null,
          ),
          chapter: 7,
        ),
      );
      await emit(
        tester,
        const ImportMarkdownFailed(
          fileName: 'bab-1-deep-work.md',
          error: LumaMarkdownError.unreadable,
        ),
      );
      expect(find.text('Bab 7 udah ada'), findsNothing);
      expect(find.text('Masuk ke buku mana?'), findsNothing);
      expect(find.text('Filenya gak kebaca'), findsOneWidget);
    });

    testWidgets('Batal closes the sheet and goes idle', (tester) async {
      await pump(tester);
      await emit(tester, ask());
      await tester.tap(find.widgetWithText(AppButton, 'Batal'));
      await settle(tester);
      expect(find.text('Masuk ke buku mana?'), findsNothing);
      expect(import.state, isA<ImportIdle>());
    });

    for (final (created, text) in [
      (false, 'Bab 7 masuk ke Atomic Habits ✨'),
      (true, 'Atomic Habits masuk rak ✨'),
    ]) {
      testWidgets('done: sheet closes, toast "$text" with Baca', (
        tester,
      ) async {
        await pump(tester);
        await emit(tester, ask());
        await emit(
          tester,
          ImportMarkdownDone(
            book: atomic.book,
            chapter: 7,
            chapterId: 70,
            created: created,
            replaced: false,
          ),
        );
        expect(find.text('Masuk ke buku mana?'), findsNothing);
        expect(find.text(text), findsOneWidget);
        expect(find.text('Baca'), findsOneWidget);
        expect(import.state, isA<ImportIdle>());
      });
    }

    for (final (failed, title, chip) in [
      (
        const ImportMarkdownFailed(
          fileName: 'bab-3.md',
          error: LumaMarkdownError.empty,
        ),
        'Filenya kosong nih',
        'bab-3.md · 0 kata',
      ),
      (
        const ImportMarkdownFailed(
          fileName: 'bab-3.md',
          error: LumaMarkdownError.badFrontmatter,
          detail: 'chapter',
          value: 'tiga',
        ),
        'Nomor babnya gak kebaca',
        'bab-3.md · nomor bab: “tiga”',
      ),
      (
        const ImportMarkdownFailed(
          fileName: 'bab-3.md',
          error: LumaMarkdownError.badFrontmatter,
          detail: 'book_key',
          value: 'Atomic Habits!',
        ),
        'Nama bukunya gak valid',
        'bab-3.md · nama buku: “Atomic Habits!”',
      ),
      (
        const ImportMarkdownFailed(
          fileName: 'bab-3.md',
          error: LumaMarkdownError.unreadable,
        ),
        'Filenya gak kebaca',
        'bab-3.md',
      ),
    ]) {
      testWidgets('failed: $title; Coba lagi reopens the picker', (
        tester,
      ) async {
        await pump(tester, b: Brightness.dark);
        await emit(tester, failed);
        expect(find.text(title), findsOneWidget);
        expect(find.text(chip), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Board 6a–6d icons: file-remove / alert / alert / file-corrupt.
        final icon = switch (failed.error) {
          LumaMarkdownError.empty => AppIcons.fileRemove,
          LumaMarkdownError.badFrontmatter => AppIcons.alert,
          LumaMarkdownError.unreadable => HugeIcons.strokeRoundedFileCorrupt,
        };
        expect(
          find.byWidgetPredicate((w) => w is AppIcon && w.icon == icon),
          findsWidgets,
        );
        if (failed.detail == 'book_key') {
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is RichText &&
                  w.text.toPlainText().contains(
                    'Ganti jadi kayak atomic-habits, atau hapus baris itu',
                  ),
            ),
            findsOneWidget,
          );
        }

        await tester.tap(find.text('Coba lagi'));
        await settle(tester);
        expect(import.picks, 1);
        expect(find.text(title), findsNothing);
      });
    }
  });
}
