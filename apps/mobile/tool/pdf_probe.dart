// Dump hasil import PDF ke .md + diagnostik, buat dicek mata (#89).
//
//   PDF_PROBE_FILES="a.pdf,b.pdf" PDF_PROBE_OUT=/tmp/probe \
//     fvm flutter test tool/pdf_probe.dart --timeout none
//
// Jalan lewat flutter_tester (butuh dart:ui buat cover), tapi pake PdfiumService
// + domain produksi apa adanya, bukan parser alternatif. Output (privat, jangan
// di-commit) = <out>/<nama>.md + <out>/<nama>.txt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/pdf_service.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/pdf_chapters.dart';
import 'package:luma/domain/pdf_layout.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

void main() {
  final files = (Platform.environment['PDF_PROBE_FILES'] ?? '')
      .split(',')
      .where((f) => f.trim().isNotEmpty)
      .toList();
  final out = Directory(
    Platform.environment['PDF_PROBE_OUT'] ?? '/tmp/pdf_probe',
  )..createSync(recursive: true);

  setUpAll(() {
    // flutter_tester: no path_provider plugin, so give pdfrx its dirs and the
    // libpdfium the native-assets build already produced (PDFIUM_PATH
    // overrides).
    Pdfrx.cacheDirectoryPath ??= Directory.systemTemp
        .createTempSync('pdfrx')
        .path;
    Pdfrx.pdfiumModulePath ??=
        Platform.environment['PDFIUM_PATH'] ??
        'build/native_assets/macos/libpdfium.dylib';
  });

  for (final path in files) {
    test('probe ${p.basename(path)}', () async {
      final name = p.basenameWithoutExtension(path);
      final log = StringBuffer();
      void say(String s) {
        log.writeln(s);
        // ignore: avoid_print
        print(s);
      }

      final clock = Stopwatch()..start();
      final PdfExtraction raw;
      try {
        raw = await const PdfiumService().extract(path);
      } on PdfImportException catch (e) {
        say('$name: FAILED $e');
        File(p.join(out.path, '$name.txt')).writeAsStringSync(log.toString());
        return;
      }
      final extractMs = clock.elapsedMilliseconds;
      clock.reset();

      const engine = PdfLayoutEngine();
      final empty = [
        for (final (i, g) in raw.pages.indexed)
          if (g.every((x) => x.char.trim().isEmpty)) i + 1,
      ];
      final lines = [
        for (final (i, g) in raw.pages.indexed)
          ...engine.glyphsToLines(g, pageNumber: i + 1),
      ];
      final body = engine.computeBodyFontSize(lines);
      final kept = engine.filterHeadersFootersAndFootnotes(
        lines,
        totalPages: raw.pageCount,
        bodyFontSize: body,
      );
      final keptSet = kept.toSet();
      final dropped = [
        for (final l in lines)
          if (!keptSet.contains(l)) l,
      ];
      final laid = layoutPdf(raw.pages, raw.outline);
      final layoutMs = clock.elapsedMilliseconds;

      say('== $name');
      say(
        'pages ${raw.pageCount}, no-text pages ${empty.length} '
        '${empty.take(20).toList()}, cover ${raw.cover != null}',
      );
      say('outline top-level ${raw.outline.length}');
      say('time: extract ${extractMs}ms, layout ${layoutMs}ms');
      say(
        'lines ${lines.length}, kept ${kept.length}, dropped ${dropped.length}, '
        'body font ${body.toStringAsFixed(4)}',
      );
      final counts = <String, int>{};
      for (final l in dropped) {
        counts[l.text] = (counts[l.text] ?? 0) + 1;
      }
      final top = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      say(
        'dropped top: ${top.take(8).map((e) => '"${e.key}"×${e.value}').join(' | ')}',
      );
      say('title candidate: ${laid.heading}');
      say('chapters ${laid.chapters.length}, chars ${laid.totalChars}');
      for (final (i, c) in laid.chapters.indexed.take(60)) {
        say(
          '  ${i + 1}. ${c.title}  [${c.paragraphs.length} para, ${c.charCount} ch]',
        );
      }

      final md = StringBuffer('# $name\n\n');
      for (final c in laid.chapters) {
        md.writeln('## ${c.title}\n');
        for (final para in c.paragraphs) {
          md.writeln(switch (para.type) {
            ParagraphType.heading => '### ${para.text}\n',
            ParagraphType.sceneBreak => '* * *\n',
            ParagraphType.paragraph => '${para.text}\n',
          });
        }
      }
      File(p.join(out.path, '$name.md')).writeAsStringSync(md.toString());
      File(p.join(out.path, '$name.txt')).writeAsStringSync(log.toString());
    }, timeout: Timeout.none);
  }
}
