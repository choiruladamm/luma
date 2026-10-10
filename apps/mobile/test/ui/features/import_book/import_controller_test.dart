import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/data/services/epub_parser.dart';
import 'package:luma/data/services/file_picker_service.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/domain/luma_markdown.dart';
import 'package:luma/ui/core/theme/stabilo_tokens.dart';
import 'package:luma/ui/features/import_book/view_models/import_view_model.dart';

class FakePicker extends FilePickerService {
  PickedFile? next;
  @override
  Future<PickedFile?> pickBook() async => next;
}

PickedFile picked(String name, Uint8List bytes) =>
    PickedFile(name: name, size: bytes.length, read: () async => bytes);

// Plain test(): the real event loop drives Drift and the parse isolates.
void main() {
  final epub = File('test/fixtures/enchiridion.epub').readAsBytesSync();
  late AppDatabase db;
  late Directory root;
  late FakePicker picker;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    root = await Directory.systemTemp.createTemp('luma_import_ui_');
    final storage = FileStorage(root);
    await storage.ensureDirs();
    picker = FakePicker();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        fileStorageProvider.overrideWithValue(storage),
        filePickerServiceProvider.overrideWithValue(picker),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  ImportController controller() =>
      container.read(importControllerProvider.notifier);
  ImportState state() => container.read(importControllerProvider);

  test('pick → processing stages → success with the new book', () async {
    final seen = <ImportStage>[];
    container.listen(importControllerProvider, (_, s) {
      if (s is ImportProcessing) seen.add(s.stage);
    }, fireImmediately: true);

    picker.next = picked('pg45109-images-3.epub', epub);
    await controller().pick();

    // "Baca file" sekejap, gak ditampilin (biar duplikat gak kedip).
    expect(
      seen.toSet(),
      ImportStage.values.toSet()..remove(ImportStage.reading),
    );
    final s = state();
    expect(s, isA<ImportSuccess>());
    expect((s as ImportSuccess).book.title, 'The Enchiridion');
  });

  /// Imports [epub] and returns when each state showed up.
  Future<List<(Duration, ImportState)>> timeline({
    Future<ParsedBook> Function(
      Uint8List bytes, {
      void Function()? onOutline,
      void Function(int done, int total)? onChapters,
    })?
    parse,
  }) async {
    final c = parse == null
        ? container
        : ProviderContainer(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              importRepositoryProvider.overrideWithValue(
                ImportRepository(db, FileStorage(root), parse: parse),
              ),
            ],
          );
    addTearDown(c.dispose);
    final clock = Stopwatch()..start();
    final seen = <(Duration, ImportState)>[];
    c.listen(
      importControllerProvider,
      (_, s) => seen.add((clock.elapsed, s)),
      fireImmediately: true,
    );
    await c
        .read(importControllerProvider.notifier)
        .importFile(picked('a.epub', epub));
    return seen;
  }

  test(
    'a fast import holds the loading until the minimum, then succeeds',
    () async {
      final seen = await timeline();
      final (at, last) = seen.last;
      expect(last, isA<ImportSuccess>());
      // Minimum loading (1.5 s), a little slack for timer rounding.
      expect(
        at,
        greaterThanOrEqualTo(
          Motion.importMin - const Duration(milliseconds: 50),
        ),
      );
      expect(
        at,
        lessThan(Motion.importMin + const Duration(milliseconds: 400)),
      );

      // 100% is on screen for the settle pause before "berhasil".
      final (doneAt, done) = seen.reversed.firstWhere(
        (e) => e.$2 is ImportProcessing,
      );
      expect((done as ImportProcessing).progress, 1);
      expect(at - doneAt, greaterThanOrEqualTo(Motion.importSettle));
      // ...and the number glides over the wait instead of jumping.
      expect(done.glide, greaterThan(Motion.progressStep));
    },
  );

  test('a slow import gets no extra hold beyond the 100% pause', () async {
    late DateTime parsed;
    final seen = await timeline(
      parse: (bytes, {onOutline, onChapters}) async {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        final book = await parseInIsolate(
          bytes,
          onOutline: onOutline,
          onChapters: onChapters,
        );
        parsed = DateTime.now();
        return book;
      },
    );
    final end = DateTime.now();
    expect(seen.last.$2, isA<ImportSuccess>());
    final (_, done) = seen.reversed.firstWhere((e) => e.$2 is ImportProcessing);
    expect((done as ImportProcessing).glide, Motion.progressStep);
    // After the parse: save + 150 ms glide + 300 ms pause, nothing more.
    expect(
      end.difference(parsed),
      lessThan(
        Motion.progressStep +
            Motion.importSettle +
            const Duration(milliseconds: 500),
      ),
    );
  });

  test('progress is real, only goes up, and ends at 100%', () async {
    final seen = await timeline();
    final progress = [
      for (final (_, s) in seen)
        if (s is ImportProcessing) s.progress,
    ];
    expect(progress.first, lessThan(0.3)); // nongol setelah baca + hash
    expect(progress.last, 1);
    expect(progress.toSet().length, greaterThan(4)); // stages + per chapter
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
  });

  test('cancelling the picker does nothing', () async {
    await controller().pick();
    expect(state(), isA<ImportIdle>());
  });

  test('the same file twice → duplicate pointing at the first book', () async {
    picker.next = picked('a.epub', epub);
    await controller().pick();
    final first = (state() as ImportSuccess).book.id;
    final clock = Stopwatch()..start();
    var flashed = false;
    container.listen(importControllerProvider, (_, s) {
      if (s is ImportProcessing) flashed = true;
    });
    await controller().pick();
    expect(flashed, isFalse); // gak ada sheet proses sebelum sheet duplikat
    expect((state() as ImportDuplicate).book.id, first);
    expect(clock.elapsed, lessThan(Motion.importMin)); // not held
  });

  test('bad files → failed with the right reason', () async {
    for (final (name, bytes, error) in [
      ('notes.pdf', epub, EpubError.notEpub),
      ('junk.epub', Uint8List.fromList([1, 2, 3]), EpubError.notEpub),
      (
        'cut.epub',
        Uint8List.sublistView(epub, 0, epub.length ~/ 2),
        EpubError.corrupt,
      ),
    ]) {
      final clock = Stopwatch()..start();
      await controller().importFile(picked(name, bytes));
      final s = state() as ImportFailed;
      expect((s.fileName, s.error), (name, error));
      expect(
        clock.elapsed,
        lessThan(Motion.importMin),
        reason: name,
      ); // not held
    }
  });

  test('Batalin goes idle right away and nothing is imported', () async {
    final run = controller().importFile(picked('a.epub', epub));
    controller().cancel();
    expect(state(), isA<ImportIdle>());
    await run;
    expect(state(), isA<ImportIdle>());
    expect(await db.select(db.books).get(), isEmpty);
  });

  group('markdown', () {
    PickedFile md(String name, String text) =>
        picked(name, Uint8List.fromList(utf8.encode(text)));
    const full = '---\nbook_key: dune\nbook: Dune\nchapter: 2\n---\n\nIsi.';

    test(
      'complete frontmatter imports straight away, no sheet state',
      () async {
        final seen = <Type>[];
        container.listen(importControllerProvider, (_, s) {
          seen.add(s.runtimeType);
        });
        await controller().importFile(md('x.md', full));

        expect(seen, [ImportMarkdownDone]);
        final s = state() as ImportMarkdownDone;
        expect((s.book.title, s.chapter, s.created), ('Dune', 2, true));
      },
    );

    test('no frontmatter asks, guesses ready; submit saves', () async {
      await controller().importFile(md('dune-bab5.md', '# Dune\n\nIsi.'));
      final ask = state() as ImportMarkdownAsk;
      expect(ask.books, isEmpty);
      expect(
        (ask.parsed.book, ask.parsed.bookKey, ask.parsed.chapter),
        ('Dune', 'dune', 5),
      );

      await controller().submitMarkdown((
        bookId: null,
        bookKey: 'dune',
        bookTitle: 'Dune',
        author: null,
        chapter: 5,
        chapterTitle: null,
      ));
      expect((state() as ImportMarkdownDone).chapter, 5);
    });

    test(
      'existing markdown books are offered, duplicate chapter asks',
      () async {
        await controller().importFile(md('a.md', full));
        controller().dismiss();

        await controller().importFile(md('b.md', 'Teks.'));
        final ask = state() as ImportMarkdownAsk;
        expect(ask.books.single.book.title, 'Dune');
        expect(ask.books.single.chapters, [2]);

        final choice = (
          bookId: ask.books.single.book.id,
          bookKey: 'dune',
          bookTitle: 'Dune',
          author: null,
          chapter: 2,
          chapterTitle: null,
        );
        await controller().submitMarkdown(choice);
        expect((state() as ImportMarkdownConflict).chapter, 2);

        await controller().confirmReplace();
        final done = state() as ImportMarkdownDone;
        expect((done.replaced, done.created), (true, false));
      },
    );

    test('bad frontmatter and empty file fail with a typed error', () async {
      for (final (text, error) in [
        ('---\nchapter: x\n---\n\nIsi.', LumaMarkdownError.badFrontmatter),
        ('# cuma heading', LumaMarkdownError.empty),
      ]) {
        await controller().importFile(md('x.md', text));
        expect((state() as ImportMarkdownFailed).error, error, reason: text);
      }
    });

    test('submit outside a pending state does nothing', () async {
      await controller().submitMarkdown((
        bookId: null,
        bookKey: 'x',
        bookTitle: 'X',
        author: null,
        chapter: null,
        chapterTitle: null,
      ));
      expect(state(), isA<ImportIdle>());
      expect(await db.select(db.books).get(), isEmpty);
    });
  });
}
