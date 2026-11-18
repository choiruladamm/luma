import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../domain/pdf_chapters.dart';
import '../../domain/pdf_layout.dart';
import 'epub_parser.dart';

/// Why a PDF import failed (docs/import-formats.md, Limits).
///
/// Cancelling is not an error: the progress callback throws `ImportCancelled`.
enum PdfImportError {
  /// The PDF is password-protected.
  // TODO(#90): ask for the password instead of failing.
  password,

  /// Most pages have no text (probably a scan).
  scan,

  /// The file is damaged or failed to open.
  corrupt,

  /// The file is not a `.pdf`.
  notPdf,

  /// The file is readable but has no text that becomes a chapter.
  empty,

  /// The file could not be read or copied.
  io,
}

class PdfImportException implements Exception {
  const PdfImportException(this.error, [this.detail]);

  final PdfImportError error;
  final String? detail;

  @override
  String toString() =>
      'PdfImportException(${error.name}${detail == null ? '' : ': $detail'})';
}

/// Holds the raw result of reading a PDF: lines per page (index 0 is page 1; a
/// page with no text is an empty list), the outline, and the cover.
///
/// The service builds lines page by page, so a whole book's glyphs never pile
/// up in memory. Cross-page layout (headers and footers, paragraphs, chapters)
/// is not done here.
typedef PdfExtraction = ({
  int pageCount,
  List<List<PdfLine>> pages,
  List<PdfOutlineEntry> outline,
  EpubCover? cover,
});

/// Wraps pdfrx.
///
/// Tests use a fake, so the native library is never called in `flutter test`.
abstract class PdfService {
  /// Opens the PDF at [path] (it can be hundreds of MB) and extracts its text.
  ///
  /// [onOpened] fires once after the document, outline, and cover are read;
  /// [onPage] fires after each page. Callbacks may throw (for example to
  /// cancel); the document is still closed.
  ///
  /// Throws [PdfImportException] (`password`, `corrupt`).
  Future<PdfExtraction> extract(
    String path, {
    void Function()? onOpened,
    void Function(int done, int total)? onPage,
  });
}

// ponytail: pdfrx 2.12 has no metadata API (title/author), so the title falls
// back to the page-1 heading, then the file name, and the author is null. Add
// it once pdfrx provides it; don't bind to FFI directly without an explicit
// decision.
class PdfiumService implements PdfService {
  const PdfiumService();

  static const _coverWidth = 600.0;
  static const _engine = PdfLayoutEngine();

  @override
  Future<PdfExtraction> extract(
    String path, {
    void Function()? onOpened,
    void Function(int done, int total)? onPage,
  }) async {
    await pdfrx.pdfrxFlutterInitialize();
    final pdfrx.PdfDocument doc;
    try {
      doc = await pdfrx.PdfDocument.openFile(
        path,
        // Returning null makes a locked PDF fail instead of prompting for a password.
        passwordProvider: () => null,
      );
    } on pdfrx.PdfPasswordException {
      throw const PdfImportException(PdfImportError.password);
    } on pdfrx.PdfException catch (e) {
      throw PdfImportException(PdfImportError.corrupt, e.message);
    }
    try {
      final outline = _outline(await doc.loadOutline());
      final cover = await _cover(doc);
      onOpened?.call();
      final total = doc.pages.length;
      final pages = <List<PdfLine>>[];
      for (final page in doc.pages) {
        // Glyphs of this page become lines right away and are dropped.
        pages.add(
          _engine.glyphsToLines(
            await _glyphs(page),
            pageNumber: page.pageNumber,
          ),
        );
        onPage?.call(page.pageNumber, total);
      }
      return (pageCount: total, pages: pages, outline: outline, cover: cover);
    } on pdfrx.PdfException catch (e) {
      throw PdfImportException(PdfImportError.corrupt, e.message);
    } finally {
      await doc.dispose();
    }
  }

  List<PdfOutlineEntry> _outline(List<pdfrx.PdfOutlineNode> nodes) => [
    for (final n in nodes)
      PdfOutlineEntry(
        title: n.title,
        pageNumber: n.dest?.pageNumber,
        children: _outline(n.children),
      ),
  ];

  // ponytail: rects are assumed to share one coordinate space with
  // page.width/height (pdfrx normalizes rotation). TODO(#89): check 2-up
  // spreads and unusual rotations against the corpus.
  //
  // PDFium glyph boxes are *tight* (a dot is tiny, `h` is taller than `a`), so
  // grouping lines by geometry fails. PDFium's own line separator ('\n' in
  // fullText) is carried as a '\n' glyph, and so are spaces: layout uses both
  // as-is (`PdfLayoutEngine`, stream-run mode).
  Future<List<PdfGlyph>> _glyphs(pdfrx.PdfPage page) async {
    final text = await page.loadText();
    if (text == null || page.width <= 0 || page.height <= 0) return const [];
    final w = page.width, h = page.height;
    final out = <PdfGlyph>[];
    var last = const PdfRectNormalized(left: 0, top: 0, width: 0, height: 0);
    void whitespace(String ch) => out.add(
      PdfGlyph(
        char: ch,
        pageNumber: page.pageNumber,
        bounds: PdfRectNormalized(
          left: last.right,
          top: last.top,
          width: 0,
          height: last.height,
        ),
      ),
    );
    final n = text.fullText.length < text.charRects.length
        ? text.fullText.length
        : text.charRects.length;
    for (var i = 0; i < n; i++) {
      final ch = text.fullText[i];
      if (ch == '\r') continue;
      if (ch == '\n') {
        if (out.isNotEmpty && out.last.char != '\n') whitespace('\n');
        continue;
      }
      if (ch.trim().isEmpty) {
        if (out.isNotEmpty && out.last.char != '\n') whitespace(' ');
        continue;
      }
      final r = text.charRects[i];
      if (r.height <= 0 || r.width < 0) continue;
      last = PdfRectNormalized(
        left: r.left / w,
        top: 1 - r.top / h,
        width: r.width / w,
        height: r.height / h,
      );
      out.add(PdfGlyph(char: ch, pageNumber: page.pageNumber, bounds: last));
    }
    return out;
  }

  /// Renders page 1 to PNG; any failure returns null (the default cover is used).
  Future<EpubCover?> _cover(pdfrx.PdfDocument doc) async {
    try {
      final page = doc.pages.first;
      final fullHeight = _coverWidth * page.height / page.width;
      final img = await page.render(
        fullWidth: _coverWidth,
        fullHeight: fullHeight,
      );
      if (img == null) return null;
      try {
        final done = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          img.pixels,
          img.width,
          img.height,
          ui.PixelFormat.bgra8888,
          done.complete,
        );
        final png = await (await done.future).toByteData(
          format: ui.ImageByteFormat.png,
        );
        return png == null ? null : EpubCover(png.buffer.asUint8List(), 'png');
      } finally {
        img.dispose();
      }
    } on Object {
      return null;
    }
  }
}

final pdfServiceProvider = Provider<PdfService>((ref) => const PdfiumService());
