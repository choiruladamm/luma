import 'package:drift/drift.dart' show Uint8List;
import 'package:luma/data/services/epub_parser.dart';
import 'package:luma/data/services/pdf_service.dart';
import 'package:luma/domain/pdf_layout.dart';

/// Glyphs for one body line of [text] at vertical position [top].
List<PdfGlyph> pdfLine(String text, double top, int page, {double h = 0.02}) =>
    [
      for (final (i, c) in text.split('').indexed)
        PdfGlyph(
          char: c,
          pageNumber: page,
          bounds: PdfRectNormalized(
            left: 0.1 + i * 0.012,
            top: top,
            width: 0.01,
            height: h,
          ),
        ),
    ];

/// Page with an optional big heading and three body lines.
List<PdfGlyph> pdfPage(int page, {String? heading, String body = 'Kata'}) => [
  if (heading != null) ...pdfLine(heading, 0.15, page, h: 0.04),
  for (var i = 0; i < 3; i++)
    ...pdfLine('$body baris ke $i di halaman $page.', 0.3 + i * 0.03, page),
];

class FakePdf implements PdfService {
  FakePdf(this.result);

  PdfExtraction result;
  Object? error;
  int calls = 0;
  void Function()? afterPages;

  @override
  Future<PdfExtraction> extract(
    String path, {
    void Function()? onOpened,
    void Function(int done, int total)? onPage,
  }) async {
    calls++;
    if (error != null) throw error!;
    onOpened?.call();
    for (var i = 1; i <= result.pageCount; i++) {
      onPage?.call(i, result.pageCount);
    }
    afterPages?.call();
    return result;
  }
}

final pdfCover = EpubCover(Uint8List.fromList([1, 2, 3]), 'png');

PdfExtraction pdfDoc(List<List<PdfGlyph>> pages, {bool cover = true}) => (
  pageCount: pages.length,
  pages: pages,
  outline: const [],
  cover: cover ? pdfCover : null,
);
