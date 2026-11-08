import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/data/repositories/reading_progress_repository.dart';
import 'package:luma/data/services/backup_service.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/data/services/pdf_service.dart';
import 'package:luma/data/services/restore_service.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/pdf_chapters.dart';

import '../support/fake_pdf.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late FileStorage storage;
  late FakePdf fake;
  late ImportRepository repo;
  late File pdf;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    root = await Directory.systemTemp.createTemp('luma_pdf_');
    storage = FileStorage(root);
    await storage.ensureDirs();
    fake = FakePdf(
      pdfDoc([
        pdfPage(1, heading: 'Chapter 1'),
        pdfPage(2),
        pdfPage(3, heading: 'Chapter 2'),
        pdfPage(4),
      ]),
    );
    repo = ImportRepository(db, storage, pdfService: fake);
    pdf = File('${root.path}/novel.pdf')..writeAsBytesSync([37, 80, 68, 70, 9]);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  String hashOf(File f) => sha256.convert(f.readAsBytesSync()).toString();

  Future<List<String>> stored() async => [
    for (final d in [storage.booksDir, storage.coversDir])
      ...d.listSync().map((f) => f.uri.pathSegments.last),
  ]..sort();

  Future<PdfImportResult> import({
    void Function(ImportStage)? onStage,
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) => repo.importPdf(
    pdf.path,
    fileName: 'novel.pdf',
    onStage: onStage,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );

  Future<void> expectNothing() async {
    expect(await db.select(db.books).get(), isEmpty);
    expect(await db.select(db.chapters).get(), isEmpty);
    expect(await db.select(db.paragraphs).get(), isEmpty);
    expect(await stored(), isEmpty);
  }

  Future<PdfImportError> failure(Future<Object?> f) async {
    try {
      await f;
    } on PdfImportException catch (e) {
      return e.error;
    }
    fail('expected PdfImportException');
  }

  test('fresh import: book row, versions, files, chapters', () async {
    final r = await import();
    expect(r.duplicate, isFalse);
    expect(r.skippedPages, 0);

    final hash = hashOf(pdf);
    final book = await db.select(db.books).getSingle();
    expect(book.id, r.bookId);
    expect(book.sourceType, SourceType.pdf);
    expect(book.parserVersion, pdfParserVersion);
    expect(book.title, 'Chapter 1'); // heading halaman 1
    expect(book.author, isNull);
    expect(book.hash, hash);
    expect(book.fileName, '$hash.pdf');
    expect(book.coverName, '$hash.png');
    expect(book.contentRevision, 1);
    expect(await stored(), ['$hash.pdf', '$hash.png']);
    expect(storage.book('$hash.pdf').readAsBytesSync(), pdf.readAsBytesSync());

    final chapters = await (db.select(
      db.chapters,
    )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();
    expect(chapters, isNotEmpty);
    expect(
      chapters.map((c) => c.sortOrder),
      List.generate(chapters.length, (i) => i),
    );
    expect(chapters.every((c) => c.section == ''), isTrue); // gak di-backfill
    expect(chapters.first.charOffset, 0);
    final paras = await db.select(db.paragraphs).get();
    expect(paras, isNotEmpty);
    expect(book.totalChars, greaterThan(0));
    final hits = await db
        .customSelect(
          'SELECT p.text FROM paragraph_fts f JOIN paragraphs p '
          'ON p.rowid = f.rowid WHERE paragraph_fts MATCH ?',
          variables: [Variable('halaman')],
        )
        .get();
    expect(hits, isNotEmpty);
  });

  test('title falls back to the file name without a heading', () async {
    fake.result = pdfDoc([pdfPage(1), pdfPage(2)], cover: false);
    await import();
    final book = await db.select(db.books).getSingle();
    expect(book.title, 'novel');
    expect(book.coverName, isNull);
    expect(await stored(), ['${hashOf(pdf)}.pdf']); // cover gagal ≠ gagal
  });

  test(
    'file-name title: underscores, double spaces and mirror tags cleaned',
    () async {
      fake.result = pdfDoc([pdfPage(1), pdfPage(2)], cover: false);
      await repo.importPdf(
        pdf.path,
        fileName: 'The_First__20_Hours (z-lib.org).pdf',
      );
      expect(
        (await db.select(db.books).getSingle()).title,
        'The First 20 Hours',
      );
    },
  );

  test('same file twice: duplicate, no second parse, nothing new', () async {
    final first = await import();
    final files = await stored();
    final second = await import();
    expect(second.duplicate, isTrue);
    expect(second.bookId, first.bookId);
    expect(fake.calls, 1);
    expect(await db.select(db.books).get(), hasLength(1));
    expect(await stored(), files);
  });

  group('errors leave nothing behind', () {
    test('password / corrupt from the service', () async {
      fake.error = const PdfImportException(PdfImportError.password);
      expect(await failure(import()), PdfImportError.password);
      fake.error = const PdfImportException(PdfImportError.corrupt, 'x');
      expect(await failure(import()), PdfImportError.corrupt);
      await expectNothing();
    });

    test('not a .pdf name', () async {
      expect(
        await failure(repo.importPdf(pdf.path, fileName: 'novel.epub')),
        PdfImportError.notPdf,
      );
      expect(fake.calls, 0);
      await expectNothing();
    });

    test('unreadable file is io, not corrupt', () async {
      expect(
        await failure(
          repo.importPdf('${root.path}/nope.pdf', fileName: 'nope.pdf'),
        ),
        PdfImportError.io,
      );
      await expectNothing();
    });

    test('scan-dominated: more than half the pages without text', () async {
      fake.result = pdfDoc([pdfPage(1), const [], const [], const []]);
      expect(await failure(import()), PdfImportError.scan);
      await expectNothing();
    });

    test('exactly half empty is a mixed PDF, not a scan', () async {
      fake.result = pdfDoc([pdfPage(1), const [], pdfPage(3), const []]);
      expect((await import()).skippedPages, 2);
    });

    test('no pages / no readable text is empty', () async {
      fake.result = pdfDoc(const []);
      expect(await failure(import()), PdfImportError.empty);
      fake.result = pdfDoc([pdfLine('12', 0.94, 1), pdfLine('13', 0.94, 2)]);
      expect(await failure(import()), PdfImportError.empty);
      await expectNothing();
    });
  });

  test('mixed PDF counts skipped pages', () async {
    fake.result = pdfDoc([
      pdfPage(1, heading: 'A'),
      const [],
      pdfPage(3),
      pdfPage(4),
    ]);
    final r = await import();
    expect(r.skippedPages, 1);
    expect(await db.select(db.books).get(), hasLength(1));
  });

  group('cancel', () {
    test('during page extraction', () async {
      var polls = 0;
      await expectLater(
        import(isCancelled: () => ++polls > 2),
        throwsA(isA<ImportCancelled>()),
      );
      await expectNothing();
    });

    test('after all pages are read, before saving', () async {
      var cancel = false;
      fake.afterPages = () => cancel = true;
      await expectLater(
        import(isCancelled: () => cancel),
        throwsA(isA<ImportCancelled>()),
      );
      await expectNothing();
    });

    test('immediately', () async {
      await expectLater(
        import(isCancelled: () => true),
        throwsA(isA<ImportCancelled>()),
      );
      expect(fake.calls, 0);
      await expectNothing();
    });
  });

  test('progress only rises, never reaches 1; stages in order', () async {
    final progress = <double>[];
    final stages = <ImportStage>[];
    await import(onProgress: progress.add, onStage: stages.add);
    expect(stages, ImportStage.values);
    expect(progress, isNotEmpty);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
    expect(progress.last, lessThan(1));
  });

  group('rollback', () {
    Future<void> breakParagraphs() => db.customStatement(
      "CREATE TRIGGER boom BEFORE INSERT ON paragraphs "
      "BEGIN SELECT RAISE(ABORT, 'boom'); END",
    );

    test('DB failure: rows rolled back, new files removed', () async {
      await breakParagraphs();
      await expectLater(import(), throwsA(isA<Exception>()));
      await expectNothing();
    });

    test('a file that predates the import survives the rollback', () async {
      await breakParagraphs();
      final name = '${hashOf(pdf)}.pdf';
      await storage.writeBook(name, pdf.readAsBytesSync());
      await expectLater(import(), throwsA(isA<Exception>()));
      expect(await db.select(db.books).get(), isEmpty);
      expect(await stored(), [name]);
      expect(storage.book(name).readAsBytesSync(), pdf.readAsBytesSync());
    });

    test('write failure is io and leaves no cover', () async {
      await storage.booksDir.delete(recursive: true);
      File(storage.booksDir.path).writeAsStringSync('in the way');
      expect(await failure(import()), PdfImportError.io);
      expect(await db.select(db.books).get(), isEmpty);
      expect(storage.coversDir.listSync(), isEmpty);
    });
  });

  test('markFinished stamps a PDF book once', () async {
    final r = await import();
    final progress = ReadingProgressRepository(db);
    await progress.markFinished(r.bookId);
    final first = (await db.select(db.books).getSingle()).finishedAt;
    expect(first, isNotNull);
    await progress.markFinished(r.bookId);
    expect((await db.select(db.books).getSingle()).finishedAt, first);
  });

  test('EPUB section backfill never parses a PDF book', () async {
    final guarded = ImportRepository(
      db,
      storage,
      pdfService: fake,
      parse: (bytes, {onOutline, onChapters}) =>
          throw StateError('must not parse a PDF'),
    );
    final r = await import();
    await guarded.backfillSections(r.bookId);
    final sections = (await db.select(db.chapters).get()).map((c) => c.section);
    expect(sections.every((s) => s == ''), isTrue);
  });

  test(
    'backup → restore keeps the PDF, content, progress and search',
    () async {
      // Dua "HP" dengan file DB beneran, kayak restore_service_test.
      Future<(Directory, FileStorage, AppDatabase)> phone() async {
        final dir = await Directory.systemTemp.createTemp('luma_pdf_phone_');
        final s = FileStorage(dir);
        await s.ensureDirs();
        return (
          dir,
          s,
          AppDatabase(NativeDatabase(File('${dir.path}/luma.sqlite'))),
        );
      }

      final (aDir, aStorage, aDb) = await phone();
      final (bDir, bStorage, bDb0) = await phone();
      addTearDown(() async {
        await aDb.close();
        await aDir.delete(recursive: true);
        await bDir.delete(recursive: true);
      });
      final r = await ImportRepository(
        aDb,
        aStorage,
        pdfService: fake,
      ).importPdf(pdf.path, fileName: 'novel.pdf');
      await aDb.customStatement(
        'UPDATE books SET reading_seconds = 99, finished_at = 1 WHERE id = ?',
        [r.bookId],
      );
      final hash = hashOf(pdf);

      final backup = (await BackupService(aDb, aStorage).export())!;
      addTearDown(backup.dispose);
      final service = RestoreService(bDb0, bStorage);
      await service.apply(await service.inspect(backup.file));
      final bDb = AppDatabase(NativeDatabase(File('${bDir.path}/luma.sqlite')));
      addTearDown(bDb.close);

      expect(
        bStorage.book('$hash.pdf').readAsBytesSync(),
        pdf.readAsBytesSync(),
      );
      final book = await bDb.select(bDb.books).getSingle();
      expect(book.sourceType, SourceType.pdf);
      expect(book.parserVersion, pdfParserVersion);
      expect(book.readingSeconds, 99);
      expect(book.fileName, '$hash.pdf');
      expect(
        (await bDb.select(bDb.paragraphs).get()).length,
        (await aDb.select(aDb.paragraphs).get()).length,
      );
      final hits = await bDb
          .customSelect(
            'SELECT p.text FROM paragraph_fts f JOIN paragraphs p '
            'ON p.rowid = f.rowid WHERE paragraph_fts MATCH ?',
            variables: [Variable('halaman')],
          )
          .get();
      expect(hits, isNotEmpty);
    },
  );
}
