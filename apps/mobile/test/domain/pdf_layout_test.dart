import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/pdf_layout.dart';

void main() {
  const engine = PdfLayoutEngine();

  PdfGlyph g(
    String char,
    double l,
    double t,
    double w,
    double h, {
    int page = 1,
    double? fontH,
  }) => PdfGlyph(
    char: char,
    bounds: PdfRectNormalized(left: l, top: t, width: w, height: h),
    pageNumber: page,
    fontHeight: fontH ?? h,
  );

  group('cleanText', () {
    test('converts ligatures to plain characters', () {
      expect(PdfLayoutEngine.cleanText('ﬁnd ﬂight oﬃce'), 'find flight office');
      expect(PdfLayoutEngine.cleanText('ﬀl ﬅ ﬆ'), 'ffl ft st');
    });

    test('strips soft hyphens, nulls, zero-widths, and normalizes NBSP', () {
      final dirty = 'Hello\u00ADworld\u0000\uFFFD\u200B \u00A0there\u202F!';
      expect(PdfLayoutEngine.cleanText(dirty), 'Helloworld  there !');
    });
  });

  group('glyphsToLines & columns', () {
    test('groups stream glyphs by position rather than insertion order', () {
      // Out of order glyphs: "C", "A", "B"
      final glyphs = [
        g('C', 0.20, 0.10, 0.05, 0.02),
        g('A', 0.10, 0.10, 0.05, 0.02),
        g('B', 0.15, 0.10, 0.05, 0.02),
      ];

      final lines = engine.glyphsToLines(glyphs, pageNumber: 1);
      expect(lines, hasLength(1));
      expect(lines.first.text, 'ABC');
    });

    test('reads two columns: left column first, then right column', () {
      // Column 1 (x: 0.10..0.45)
      // Column 2 (x: 0.55..0.90)
      final glyphs = [
        // Col 2 line 1
        g('R', 0.55, 0.10, 0.05, 0.02),
        g('1', 0.60, 0.10, 0.05, 0.02),
        // Col 1 line 1
        g('L', 0.10, 0.10, 0.05, 0.02),
        g('1', 0.15, 0.10, 0.05, 0.02),
        // Col 1 line 2
        g('L', 0.10, 0.14, 0.05, 0.02),
        g('2', 0.15, 0.14, 0.05, 0.02),
        // Col 2 line 2
        g('R', 0.55, 0.14, 0.05, 0.02),
        g('2', 0.60, 0.14, 0.05, 0.02),
      ];

      final lines = engine.glyphsToLines(glyphs, pageNumber: 1);
      final texts = lines.map((l) => l.text).toList();
      expect(texts, ['L1', 'L2', 'R1', 'R2']);
    });

    test('full-width top heading is read before two columns', () {
      final glyphs = [
        // Spanning title at top
        g('Title Across Columns', 0.10, 0.05, 0.75, 0.03, fontH: 0.03),
        // Col 1 line
        g('Left text', 0.10, 0.15, 0.30, 0.02),
        // Col 2 line
        g('Right text', 0.55, 0.15, 0.30, 0.02),
      ];

      final lines = engine.glyphsToLines(glyphs, pageNumber: 1);
      final texts = lines.map((l) => l.text).toList();
      expect(texts, ['Title Across Columns', 'Left text', 'Right text']);
    });
  });

  group('computeBodyFontSize', () {
    test('finds character-weighted mode font size', () {
      final lines = [
        PdfLine(
          text: 'Short Heading',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.1,
            width: 0.5,
            height: 0.03,
          ),
          pageNumber: 1,
          fontHeight: 0.030,
        ),
        PdfLine(
          text: 'This is a much longer body paragraph line with plenty of characters.',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.2,
            width: 0.8,
            height: 0.015,
          ),
          pageNumber: 1,
          fontHeight: 0.015,
        ),
      ];

      final bodySize = engine.computeBodyFontSize(lines);
      expect(bodySize, 0.015);
    });
  });

  group('filterHeadersFootersAndFootnotes', () {
    test('removes recurring headers appearing on >= 30% pages', () {
      final allLines = <PdfLine>[];
      // 10 pages total
      for (var page = 1; page <= 10; page++) {
        // Recurring header
        allLines.add(
          PdfLine(
            text: 'PRIDE AND PREJUDICE',
            bounds: const PdfRectNormalized(
              left: 0.3,
              top: 0.03,
              width: 0.4,
              height: 0.02,
            ),
            pageNumber: page,
            fontHeight: 0.012,
          ),
        );
        // Body text
        allLines.add(
          PdfLine(
            text: 'Page $page story sentence.',
            bounds: const PdfRectNormalized(
              left: 0.1,
              top: 0.3,
              width: 0.6,
              height: 0.02,
            ),
            pageNumber: page,
            fontHeight: 0.015,
          ),
        );
      }

      final filtered = engine.filterHeadersFootersAndFootnotes(
        allLines,
        totalPages: 10,
        bodyFontSize: 0.015,
      );

      expect(filtered.any((l) => l.text == 'PRIDE AND PREJUDICE'), isFalse);
      expect(filtered.where((l) => l.text.startsWith('Page ')), hasLength(10));
    });

    test('removes standalone page numbers (arabic and roman)', () {
      final lines = [
        PdfLine(
          text: '12',
          bounds: const PdfRectNormalized(
            left: 0.48,
            top: 0.04,
            width: 0.04,
            height: 0.02,
          ),
          pageNumber: 12,
          fontHeight: 0.012,
        ),
        PdfLine(
          text: '- xiv -',
          bounds: const PdfRectNormalized(
            left: 0.45,
            top: 0.95,
            width: 0.1,
            height: 0.02,
          ),
          pageNumber: 14,
          fontHeight: 0.012,
        ),
        PdfLine(
          text: 'Legitimate story body text mentioning chapter 12.',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.5,
            width: 0.7,
            height: 0.02,
          ),
          pageNumber: 12,
          fontHeight: 0.015,
        ),
      ];

      final filtered = engine.filterHeadersFootersAndFootnotes(
        lines,
        totalPages: 20,
        bodyFontSize: 0.015,
      );

      expect(filtered, hasLength(1));
      expect(
        filtered.first.text,
        'Legitimate story body text mentioning chapter 12.',
      );
    });

    test('removes footnotes in bottom margin with smaller font', () {
      final lines = [
        PdfLine(
          text: 'Main body mentioning a note.',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.6,
            width: 0.7,
            height: 0.02,
          ),
          pageNumber: 1,
          fontHeight: 0.015,
        ),
        PdfLine(
          text: '1. This is a footnote explanation.',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.94,
            width: 0.6,
            height: 0.01,
          ),
          pageNumber: 1,
          fontHeight: 0.010, // < 0.85 * 0.015
        ),
      ];

      final filtered = engine.filterHeadersFootersAndFootnotes(
        lines,
        totalPages: 1,
        bodyFontSize: 0.015,
      );

      expect(filtered, hasLength(1));
      expect(filtered.first.text, 'Main body mentioning a note.');
    });
  });

  group('processToBlocks', () {
    test('merges drop cap into next line', () {
      final lines = [
        PdfLine(
          text: 'I',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.2,
            width: 0.05,
            height: 0.04,
          ),
          pageNumber: 1,
          fontHeight: 0.035, // Drop cap
        ),
        PdfLine(
          text: 't is a truth universally acknowledged.',
          bounds: const PdfRectNormalized(
            left: 0.16,
            top: 0.2,
            width: 0.6,
            height: 0.015,
          ),
          pageNumber: 1,
          fontHeight: 0.015,
        ),
      ];

      final blocks = engine.processToBlocks(lines, bodyFontSize: 0.015);
      expect(blocks, hasLength(1));
      expect(blocks.first.type, ParagraphType.paragraph);
      expect(blocks.first.text, 'It is a truth universally acknowledged.');
    });

    test('detects headings by font size scale and keyword pattern', () {
      final lines = [
        PdfLine(
          text: 'CHAPTER 1',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.15,
            width: 0.3,
            height: 0.025,
          ),
          pageNumber: 1,
          fontHeight: 0.025, // >= 1.2 * 0.015
        ),
        PdfLine(
          text: 'First paragraph of the chapter.',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.25,
            width: 0.7,
            height: 0.015,
          ),
          pageNumber: 1,
          fontHeight: 0.015,
        ),
      ];

      final blocks = engine.processToBlocks(lines, bodyFontSize: 0.015);
      expect(blocks, hasLength(2));
      expect(blocks[0].type, ParagraphType.heading);
      expect(blocks[0].text, 'CHAPTER 1');
      expect(blocks[1].type, ParagraphType.paragraph);
      expect(blocks[1].text, 'First paragraph of the chapter.');
    });

    test('detects scene break symbols', () {
      final lines = [
        PdfLine(
          text: 'Ending sentence before break.',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.3,
            width: 0.6,
            height: 0.015,
          ),
          pageNumber: 1,
          fontHeight: 0.015,
        ),
        PdfLine(
          text: '* * *',
          bounds: const PdfRectNormalized(
            left: 0.45,
            top: 0.36,
            width: 0.1,
            height: 0.015,
          ),
          pageNumber: 1,
          fontHeight: 0.015,
        ),
        PdfLine(
          text: 'Starting sentence after break.',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.42,
            width: 0.6,
            height: 0.015,
          ),
          pageNumber: 1,
          fontHeight: 0.015,
        ),
      ];

      final blocks = engine.processToBlocks(lines, bodyFontSize: 0.015);
      expect(blocks, hasLength(3));
      expect(blocks[1].type, ParagraphType.sceneBreak);
      expect(blocks[1].text, '***');
    });

    test('reconnects hyphenated word cut across lines', () {
      final lines = [
        PdfLine(
          text: 'This system provides kon-',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.20,
            width: 0.7,
            height: 0.015,
          ),
          pageNumber: 1,
          fontHeight: 0.015,
        ),
        PdfLine(
          text: 'tinuity for long reading sessions.',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.23,
            width: 0.7,
            height: 0.015,
          ),
          pageNumber: 1,
          fontHeight: 0.015,
        ),
      ];

      final blocks = engine.processToBlocks(lines, bodyFontSize: 0.015);
      expect(blocks, hasLength(1));
      expect(
        blocks.first.text,
        'This system provides kontinuitas for long reading sessions.'
            .replaceAll('kontinuitas', 'kontinuity'),
      );
    });

    test('connects paragraph spanning across page boundary', () {
      final lines = [
        // Page 1 line ending without punctuation
        PdfLine(
          text: 'The travelers walked through the quiet valley and reached',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.90,
            width: 0.7,
            height: 0.015,
          ),
          pageNumber: 1,
          fontHeight: 0.015,
        ),
        // Page 2 line continuing with lowercase
        PdfLine(
          text: 'the ancient fortress before sunset.',
          bounds: const PdfRectNormalized(
            left: 0.1,
            top: 0.10,
            width: 0.7,
            height: 0.015,
          ),
          pageNumber: 2,
          fontHeight: 0.015,
        ),
      ];

      final blocks = engine.processToBlocks(lines, bodyFontSize: 0.015);
      expect(blocks, hasLength(1));
      expect(
        blocks.first.text,
        'The travelers walked through the quiet valley and reached the ancient fortress before sunset.',
      );
    });

    test(
      'preserves distinct paragraphs when previous line ends with period',
      () {
        final lines = [
          PdfLine(
            text: 'First complete paragraph.',
            bounds: const PdfRectNormalized(
              left: 0.1,
              top: 0.20,
              width: 0.5,
              height: 0.015,
            ),
            pageNumber: 1,
            fontHeight: 0.015,
          ),
          PdfLine(
            text: 'Second independent paragraph.',
            bounds: const PdfRectNormalized(
              left: 0.1,
              top: 0.28,
              width: 0.5,
              height: 0.015,
            ),
            pageNumber: 1,
            fontHeight: 0.015,
          ),
        ];

        final blocks = engine.processToBlocks(lines, bodyFontSize: 0.015);
        expect(blocks, hasLength(2));
        expect(blocks[0].text, 'First complete paragraph.');
        expect(blocks[1].text, 'Second independent paragraph.');
      },
    );
  });

  group('tight glyph boxes (real PDFium output)', () {
    // PDFium boxes are tight: `h`/`l` are taller than `a`/`o`, a period is a
    // tiny dot on the baseline. Boxes sit on a shared baseline (bottom).
    List<PdfGlyph> printed(String text, double baseline, {double left = 0.1}) {
      const tall = 'hlbdkftT';
      var x = left;
      final out = <PdfGlyph>[];
      for (final c in text.split('')) {
        if (c == ' ') {
          out.add(g(' ', x, baseline, 0, 0));
          x += 0.01;
          continue;
        }
        final h = c == '.' || c == ','
            ? 0.003
            : tall.contains(c)
            ? 0.014
            : 0.009;
        out.add(g(c, x, baseline - h, 0.008, h));
        x += 0.01;
      }
      return out;
    }

    test('PDFium line breaks win over box geometry', () {
      final glyphs = [
        ...printed('the hall.', 0.30),
        g('\n', 0.2, 0.3, 0, 0),
        ...printed('old bell,', 0.33),
      ];
      final lines = engine.glyphsToLines(glyphs, pageNumber: 1);
      expect(lines.map((l) => l.text), ['the hall.', 'old bell,']);
      expect(lines[0].baseline, closeTo(0.30, 1e-9));
      expect(lines[0].charWidth, closeTo(0.008, 1e-9));
    });

    test('scrambled stream order still reads top to bottom', () {
      final glyphs = [
        ...printed('second', 0.34),
        g('\n', 0.2, 0.34, 0, 0),
        ...printed('first', 0.30),
      ];
      final lines = engine.glyphsToLines(glyphs, pageNumber: 1);
      expect(lines.map((l) => l.text), ['first', 'second']);
    });

    PdfLine line(String t, double base, double left) => PdfLine(
      text: t,
      bounds: PdfRectNormalized(
        left: left,
        top: base - 0.014,
        width: 0.5,
        height: 0.018,
      ),
      pageNumber: 1,
      fontHeight: 0.009,
      baselineY: base,
      medianGlyphWidth: 0.008,
    );

    test('indent starts a paragraph, side-bearing jitter does not', () {
      final blocks = engine.processToBlocks([
        line('One line of text here', 0.30, 0.100),
        line('another line of it', 0.32, 0.1015), // jitter
        line('Indented new paragraph', 0.34, 0.120), // 2.5 glyph widths
        line('and its second line', 0.36, 0.100),
      ], bodyFontSize: 0.009);
      expect(blocks.map((b) => b.text), [
        'One line of text here another line of it',
        'Indented new paragraph and its second line',
      ]);
    });

    test('baseline gap larger than the line pitch splits', () {
      final blocks = engine.processToBlocks([
        line('a', 0.30, 0.1),
        line('b', 0.32, 0.1),
        line('c', 0.34, 0.1),
        line('d after a blank line', 0.40, 0.1),
      ], bodyFontSize: 0.009);
      expect(blocks.map((b) => b.text), ['a b c', 'd after a blank line']);
    });
  });

  group('line-end hyphens', () {
    PdfLine l(String t, double base) => PdfLine(
      text: t,
      bounds: PdfRectNormalized(
        left: 0.1,
        top: base - 0.014,
        width: 0.5,
        height: 0.018,
      ),
      pageNumber: 1,
      fontHeight: 0.009,
      baselineY: base,
      medianGlyphWidth: 0.008,
    );

    String one(String a, String b) => engine
        .processToBlocks([l(a, 0.30), l(b, 0.32)], bodyFontSize: 0.009)
        .single
        .text;

    test('soft hyphen joins the word', () {
      expect(one('a conti-', 'nuous line'), 'a continuous line');
    });

    test('compound heads keep the hyphen', () {
      expect(one('about two-', 'thirds of it'), 'about two-thirds of it');
      expect(one('a three-', 'character group'), 'a three-character group');
    });
  });

  group('real-book text details (tight boxes)', () {
    const tall = 'hlbdkftTHOF';
    List<PdfGlyph> printed(
      String text,
      double baseline, {
      double left = 0.1,
      double step = 0.01,
      double raise = 0,
    }) {
      var x = left;
      final out = <PdfGlyph>[];
      for (final c in text.split('')) {
        if (c == ' ') {
          out.add(g(' ', x, baseline, 0, 0));
          x += step;
          continue;
        }
        final h = c == '.' || c == ','
            ? 0.003
            : tall.contains(c)
            ? 0.014
            : 0.009;
        out.add(g(c, x, baseline - h - raise, 0.008, h));
        x += step;
      }
      return out;
    }

    test('raised footnote digits are dropped, baseline digits stay', () {
      final base = printed('Died in 65 AD. Next', 0.30);
      final mark = printed('3', 0.30, left: 0.1 + 14 * 0.01, raise: 0.006);
      // Insert the raised "3" right after "AD." (index 14) in stream order.
      final glyphs = [
        ...base.take(14),
        ...mark,
        ...base.skip(14),
        g('\n', 0.3, 0.3, 0, 0),
      ];
      final lines = engine.glyphsToLines(glyphs, pageNumber: 1);
      expect(lines.single.text, 'Died in 65 AD. Next');
    });

    test('a line made only of a raised digit is kept (not emptied)', () {
      final glyphs = [
        ...printed('7', 0.30, raise: 0.006),
        g('\n', 0.2, 0.3, 0, 0),
      ];
      expect(engine.glyphsToLines(glyphs, pageNumber: 1).single.text, '7');
    });

    test('a wide gap with no space glyph becomes a space, quotes do not', () {
      final glyphs = [
        ...printed('THE FATE OF', 0.30),
        // The next run starts after a clear gap but PDFium emitted no space.
        ...printed('British', 0.30, left: 0.1 + 11 * 0.01 + 0.006),
        g('\n', 0.3, 0.3, 0, 0),
        ...printed('it’', 0.32),
        ...printed('s', 0.32, left: 0.1 + 3 * 0.01 + 0.006),
        g('\n', 0.3, 0.3, 0, 0),
      ];
      final lines = engine.glyphsToLines(glyphs, pageNumber: 1);
      expect(lines.map((l) => l.text), ['THE FATE OF British', 'it’s']);
    });

    test(
      'without PDFium line breaks: baseline clustering still reads lines',
      () {
        // No '\n' glyphs at all (fallback path), tight boxes, ascenders vary.
        final glyphs = [
          ...printed('the hall.', 0.30),
          ...printed('old bell,', 0.33),
          ...printed('big dog', 0.36),
        ];
        final lines = engine.glyphsToLines(glyphs, pageNumber: 1);
        expect(lines.map((l) => l.text), ['the hall.', 'old bell,', 'big dog']);
      },
    );
  });
}
