import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../domain/pdf_chapters.dart';
import '../../domain/pdf_layout.dart';
import 'epub_parser.dart';

/// Kenapa import PDF gagal (docs/import-formats.md, Edge case). Cancel bukan
/// error: dilempar `ImportCancelled` dari callback progres.
enum PdfImportError {
  /// Ber-password (input password ditunda, #90).
  password,

  /// Mayoritas halaman tanpa teks (kemungkinan scan).
  scan,

  /// Rusak atau gagal dibuka.
  corrupt,

  /// Bukan `.pdf`.
  notPdf,

  /// Bisa dibaca tapi gak ada teks yang jadi bab.
  empty,

  /// File gak kebaca / gak bisa disalin.
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

/// Hasil baca PDF mentah: huruf per halaman (indeks 0 = halaman 1; halaman
/// tanpa teks = list kosong), outline, dan cover. Tanpa layout.
typedef PdfExtraction = ({
  int pageCount,
  List<List<PdfGlyph>> pages,
  List<PdfOutlineEntry> outline,
  EpubCover? cover,
});

/// Pembungkus pdfrx. Test pakai fake, jadi native lib gak pernah kepanggil di
/// `flutter test`.
abstract class PdfService {
  /// Buka lewat path (PDF bisa ratusan MB). [onOpened] dipanggil sekali abis
  /// dokumen + outline + cover kebaca; [onPage] tiap halaman selesai. Callback
  /// boleh lempar (mis. cancel): dokumen tetap ditutup.
  ///
  /// Lempar [PdfImportException] (`password`, `corrupt`).
  Future<PdfExtraction> extract(
    String path, {
    void Function()? onOpened,
    void Function(int done, int total)? onPage,
  });
}

// ponytail: pdfrx 2.12 gak punya API metadata (judul/penulis), jadi judul jatuh
// ke heading halaman 1 → nama file, penulis null. Tambah kalau pdfrx nyediain,
// jangan pasang FFI langsung diam-diam (keputusan #84).
class PdfiumService implements PdfService {
  const PdfiumService();

  static const _coverWidth = 600.0;

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
        // Tanpa passwordProvider: PDF terkunci gagal, bukan minta input.
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
      final pages = <List<PdfGlyph>>[];
      for (final page in doc.pages) {
        pages.add(await _glyphs(page));
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

  // ponytail: rect dianggap satu ruang dengan page.width/height (rotasi
  // dinormalisasi pdfrx). Spread 2-up / rotasi aneh dicek di korpus (#89).
  Future<List<PdfGlyph>> _glyphs(pdfrx.PdfPage page) async {
    final text = await page.loadText();
    if (text == null || page.width <= 0 || page.height <= 0) return const [];
    final w = page.width, h = page.height;
    final out = <PdfGlyph>[];
    final n = text.fullText.length < text.charRects.length
        ? text.fullText.length
        : text.charRects.length;
    for (var i = 0; i < n; i++) {
      final ch = text.fullText[i];
      final r = text.charRects[i];
      if (ch == '\n' || ch == '\r' || r.height <= 0) continue;
      out.add(
        PdfGlyph(
          char: ch,
          pageNumber: page.pageNumber,
          bounds: PdfRectNormalized(
            left: r.left / w,
            top: 1 - r.top / h,
            width: r.width / w,
            height: r.height / h,
          ),
        ),
      );
    }
    return out;
  }

  /// Render halaman 1 → PNG. Gagal apa pun = null (cover default).
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
