// Runs the production importPdf (real PDFium, in-memory DB) over PDFs and
// prints the outcome: book title/chapters/skipped pages, or the typed error.
//
//   PDF_PROBE_FILES="a.pdf,b.pdf" fvm flutter test tool/pdf_import_check.dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/database/app_database.dart';
import 'package:luma/data/repositories/import_repository.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:luma/data/services/pdf_service.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

void main() {
  final files = (Platform.environment['PDF_PROBE_FILES'] ?? '')
      .split(',')
      .where((f) => f.trim().isNotEmpty);
  setUpAll(() {
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp
        .createTempSync('pdfrx')
        .path;
    Pdfrx.pdfiumModulePath ??=
        Platform.environment['PDFIUM_PATH'] ??
        'build/native_assets/macos/libpdfium.dylib';
  });
  for (final path in files) {
    test('import ${p.basename(path)}', () async {
      final db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final root = await Directory.systemTemp.createTemp('pdf_check_');
      final storage = FileStorage(root);
      await storage.ensureDirs();
      final repo = ImportRepository(db, storage);
      try {
        final r = await repo.importPdf(path, fileName: p.basename(path));
        final book = await db.select(db.books).getSingle();
        final n = (await db.select(db.chapters).get()).length;
        // ignore: avoid_print
        print(
          '${p.basename(path)}: OK title="${book.title}" chapters=$n '
          'skipped=${r.skippedPages} cover=${book.coverName != null}',
        );
      } on PdfImportException catch (e) {
        // ignore: avoid_print
        print('${p.basename(path)}: ${e.error.name} (${e.detail})');
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    });
  }
}
