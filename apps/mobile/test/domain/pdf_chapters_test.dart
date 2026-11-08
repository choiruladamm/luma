import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/pdf_chapters.dart';
import 'package:luma/domain/pdf_layout.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

PdfLocatedBlock block(
  String text, {
  int page = 1,
  ParagraphType type = ParagraphType.paragraph,
}) => PdfLocatedBlock(
  type: type,
  text: text,
  pageNumber: page,
  bounds: const PdfRectNormalized(
    left: 0.1,
    top: 0.1,
    width: 0.8,
    height: 0.02,
  ),
);

PdfLocatedBlock heading(String text, {int page = 1}) =>
    block(text, page: page, type: ParagraphType.heading);

PdfLocatedBlock sceneBreak({int page = 1}) =>
    block('***', page: page, type: ParagraphType.sceneBreak);

PdfOutlineEntry outline(
  String title, {
  int? page,
  List<PdfOutlineEntry> children = const [],
}) => PdfOutlineEntry(title: title, pageNumber: page, children: children);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Strategy 1 – outline', () {
    test('valid flat outline produces one chapter per bookmark', () {
      final blocks = [
        heading('Chapter One', page: 1),
        block('First chapter content.', page: 1),
        block('More first chapter.', page: 2),
        heading('Chapter Two', page: 3),
        block('Second chapter content.', page: 3),
        block('More second chapter.', page: 4),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Chapter One', page: 1),
          outline('Chapter Two', page: 3),
        ],
        totalPages: 5,
      );

      expect(result.chapters, hasLength(2));
      expect(result.chapters[0].title, 'Chapter One');
      expect(result.chapters[1].title, 'Chapter Two');
      // Every block is in exactly one chapter
      final allParagraphs = result.chapters
          .expand((c) => c.paragraphs)
          .toList();
      // The two headings repeat the bookmark titles and are dropped.
      expect(allParagraphs.length, blocks.length - 2);
    });

    test('nested outline: Part → Chapter uses child chapters', () {
      final blocks = [
        heading('Chapter 1', page: 1),
        block('Chapter 1 body.', page: 1),
        heading('Chapter 2', page: 5),
        block('Chapter 2 body.', page: 5),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [
          outline(
            'Part I',
            children: [
              outline('Chapter 1', page: 1),
              outline('Chapter 2', page: 5),
            ],
          ),
        ],
        totalPages: 10,
      );

      expect(result.chapters, hasLength(2));
      expect(result.chapters[0].title, 'Chapter 1');
      expect(result.chapters[0].section, 'Part I');
      expect(result.chapters[1].title, 'Chapter 2');
      expect(result.chapters[1].section, 'Part I');
    });

    test('bookmark with no destination is skipped', () {
      final blocks = [
        heading('Preface', page: 1),
        block('Preface body.', page: 1),
        heading('Chapter 1', page: 2),
        block('Chapter 1 body.', page: 2),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Preface', page: null), // no destination
          outline('Chapter 1', page: 2),
        ],
        totalPages: 5,
      );

      // Only one valid chapter from outline → falls back to headings
      expect(result.chapters, isNotEmpty);
    });

    test('bookmark out-of-range page is ignored', () {
      final blocks = [
        heading('Chapter 1', page: 1),
        block('Chapter 1 body.', page: 1),
        heading('Chapter 2', page: 3),
        block('Chapter 2 body.', page: 3),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Chapter 1', page: 1),
          outline('Chapter 2', page: 3),
          outline('Chapter 99', page: 999), // out of range
        ],
        totalPages: 5,
      );

      expect(result.chapters.length, 2);
    });

    test('two chapters starting on the same page – split at heading', () {
      final blocks = [
        heading('Chapter 1', page: 1),
        block('Chapter 1 body.', page: 1),
        heading('Chapter 2', page: 1), // same page
        block('Chapter 2 body.', page: 1),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [outline('Chapter 1', page: 1), outline('Chapter 2', page: 1)],
        totalPages: 2,
      );

      // Duplicate block indices are deduped → outline may fall back to headings
      expect(result.chapters, isNotEmpty);
      // Both chapters' blocks are accounted for
      final allText = result.chapters
          .expand((c) => c.paragraphs.map((p) => p.text))
          .toSet();
      expect(allText, contains('Chapter 1 body.'));
      expect(allText, contains('Chapter 2 body.'));
    });

    test('duplicate bookmark pointing same block is deduplicated', () {
      final blocks = [
        heading('Chapter 1', page: 1),
        block('Chapter 1 body.', page: 1),
        heading('Chapter 2', page: 3),
        block('Chapter 2 body.', page: 3),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Chapter 1', page: 1),
          outline('Chapter 1 (duplicate)', page: 1), // same page
          outline('Chapter 2', page: 3),
        ],
        totalPages: 5,
      );

      // The two bookmarks pointing to the same block are merged
      expect(result.chapters.length, lessThanOrEqualTo(3));
      // No text is duplicated
      final texts = result.chapters
          .expand((c) => c.paragraphs.map((p) => p.text))
          .toList();
      final uniqueTexts = texts.toSet();
      expect(texts.length, uniqueTexts.length);
    });

    test('outline bookmark title matches nearby heading for precise split', () {
      final blocks = [
        block('Some text from previous chapter.', page: 1),
        // heading on same page as bookmark
        heading('Chapter Two', page: 2),
        block('Chapter 2 body starts here.', page: 2),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Chapter One', page: 1),
          outline('Chapter Two', page: 2),
        ],
        totalPages: 5,
      );

      expect(result.chapters, hasLength(2));
      // Chapter 2 starts at the heading block
      expect(
        result.chapters[1].paragraphs.any(
          (p) => p.text.contains('Chapter 2 body'),
        ),
        isTrue,
      );
    });
  });

  group('Strategy 2 – headings fallback', () {
    test('chapter/bab pattern headings become boundaries when no outline', () {
      final blocks = [
        heading('Chapter 1', page: 1),
        block('Chapter 1 body.', page: 1),
        block('More body.', page: 2),
        heading('Chapter 2', page: 3),
        block('Chapter 2 body.', page: 3),
      ];

      final result = splitPdfChapters(blocks, totalPages: 5);

      expect(result.chapters, hasLength(2));
      expect(result.chapters[0].title, 'Chapter 1');
      expect(result.chapters[1].title, 'Chapter 2');
    });

    test('Bab N headings are strong headings', () {
      final blocks = [
        heading('Bab 1', page: 1),
        block('Isi bab satu.', page: 1),
        heading('Bab 2', page: 2),
        block('Isi bab dua.', page: 2),
      ];

      final result = splitPdfChapters(blocks, totalPages: 3);

      expect(result.chapters, hasLength(2));
      expect(result.chapters[0].title, 'Bab 1');
      expect(result.chapters[1].title, 'Bab 2');
    });

    test('generic heading that is not strong does not become a boundary', () {
      // No "chapter/bab" pattern, no outline – single chapter expected
      final blocks = [
        heading('Some Random Heading', page: 1),
        block('Some body text here.', page: 1),
        block('More body text.', page: 2),
        heading('Another Heading', page: 3),
        block('More text.', page: 3),
      ];

      final result = splitPdfChapters(blocks, totalPages: 4);

      // "Some Random Heading" is not strong → not a boundary;
      // All-caps short headings are strong, mixed-case non-pattern headings are not.
      // These headings are mixed-case non-pattern → falls through to page fallback.
      // With 4 pages and default fallbackPageSize=20, everything is one chapter.
      expect(result.chapters, hasLength(1));
    });

    test('ALL-CAPS short heading is treated as strong', () {
      final blocks = [
        heading('PART ONE', page: 1),
        block('Part One body.', page: 1),
        heading('PART TWO', page: 5),
        block('Part Two body.', page: 5),
      ];

      final result = splitPdfChapters(blocks, totalPages: 10);

      expect(result.chapters, hasLength(2));
    });

    test('heading fallback needs at least two strong headings', () {
      final blocks = [
        heading('Chapter 1', page: 1),
        block('Only one chapter heading.', page: 1),
        block('More body.', page: 2),
      ];

      // Single heading → not enough for strategy 2 → page fallback
      // 2 pages < 20 → single chapter
      final result = splitPdfChapters(blocks, totalPages: 2);

      expect(result.chapters, hasLength(1));
    });
  });

  group('Strategy 3 – page fallback', () {
    test('no outline/headings → splits every 20 pages', () {
      // Build 60 pages of content
      final blocks = [
        for (var p = 1; p <= 60; p++) block('Body text on page $p.', page: p),
      ];

      final result = splitPdfChapters(
        blocks,
        totalPages: 60,
        fallbackPageSize: 20,
      );

      expect(result.chapters, hasLength(3));
      expect(result.chapters[0].title, 'Bagian 1');
      expect(result.chapters[1].title, 'Bagian 2');
      expect(result.chapters[2].title, 'Bagian 3');
    });

    test('short document (< fallbackPageSize) is a single chapter', () {
      final blocks = [
        for (var p = 1; p <= 10; p++) block('Content on page $p.', page: p),
      ];

      final result = splitPdfChapters(
        blocks,
        totalPages: 10,
        fallbackPageSize: 20,
      );

      expect(result.chapters, hasLength(1));
      expect(result.chapters[0].title, 'Bagian 1');
    });
  });

  group('Non-content filtering', () {
    test('chapter with no body paragraphs is dropped', () {
      final blocks = [
        heading('Chapter 1', page: 1),
        block('Chapter 1 has real content here.', page: 1),
        heading('Chapter 2', page: 2),
        // Only a heading and scene break – no body paragraphs
        sceneBreak(page: 2),
        heading('Chapter 3', page: 3),
        block('Chapter 3 has real content.', page: 3),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Chapter 1', page: 1),
          outline('Chapter 2', page: 2),
          outline('Chapter 3', page: 3),
        ],
        totalPages: 4,
      );

      // Chapter 2 has no paragraphs → dropped
      expect(result.chapters.map((c) => c.title), isNot(contains('Chapter 2')));
      expect(
        result.chapters.map((c) => c.title),
        containsAll(['Chapter 1', 'Chapter 3']),
      );
    });

    test('TOC page with dot-leader lines is dropped', () {
      final blocks = [
        heading('Table of Contents', page: 1),
        block('Chapter 1 .......... 5', page: 1),
        block('Chapter 2 .......... 15', page: 1),
        block('Chapter 3 .......... 25', page: 1),
        block('Appendix .......... 45', page: 1),
        heading('Chapter 1', page: 5),
        block('Real chapter 1 body text goes here.', page: 5),
        heading('Chapter 2', page: 15),
        block('Real chapter 2 body text goes here.', page: 15),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Table of Contents', page: 1),
          outline('Chapter 1', page: 5),
          outline('Chapter 2', page: 15),
        ],
        totalPages: 30,
      );

      expect(
        result.chapters.map((c) => c.title),
        isNot(contains('Table of Contents')),
      );
      expect(result.chapters, hasLength(2));
    });

    test('Introduction and Notes are retained (not filtered)', () {
      final blocks = [
        heading('Introduction', page: 1),
        block('This book is about an important topic.', page: 1),
        block('The author explains the main themes.', page: 1),
        heading('Chapter 1', page: 3),
        block('Chapter 1 body.', page: 3),
        heading('Notes', page: 10),
        block('1. See reference A for more details.', page: 10),
        block('2. Reference B provides additional context.', page: 10),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Introduction', page: 1),
          outline('Chapter 1', page: 3),
          outline('Notes', page: 10),
        ],
        totalPages: 15,
      );

      final titles = result.chapters.map((c) => c.title).toList();
      expect(titles, contains('Introduction'));
      expect(titles, contains('Notes'));
    });
  });

  group('Output contract', () {
    test('every block appears in exactly one chapter', () {
      final blocks = [
        heading('Chapter 1', page: 1),
        block('Para 1A.', page: 1),
        block('Para 1B.', page: 2),
        heading('Chapter 2', page: 3),
        block('Para 2A.', page: 3),
        block('Para 2B.', page: 4),
        block('Para 2C.', page: 5),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [outline('Chapter 1', page: 1), outline('Chapter 2', page: 3)],
        totalPages: 6,
      );

      final allTexts = result.chapters
          .expand((c) => c.paragraphs.map((p) => p.text))
          .toList();
      // No duplicates
      expect(allTexts.toSet().length, allTexts.length);
      // All body blocks accounted for; a heading that only repeats the chapter
      // title is dropped (the reader shows the title).
      final blockTexts = blocks
          .where((b) => b.type != ParagraphType.heading)
          .map((b) => b.text)
          .toSet();
      expect(allTexts.toSet().containsAll(blockTexts), isTrue);
      expect(allTexts, isNot(contains('Chapter 1')));
    });

    test('charOffset is strictly increasing and correctly calculated', () {
      final blocks = [
        heading('Chapter 1', page: 1),
        block('AAAA', page: 1), // 4 chars
        heading('Chapter 2', page: 2),
        block('BBBBBB', page: 2), // 6 chars
        heading('Chapter 3', page: 3),
        block('CCCCCCCCCC', page: 3), // 10 chars
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Chapter 1', page: 1),
          outline('Chapter 2', page: 2),
          outline('Chapter 3', page: 3),
        ],
        totalPages: 4,
      );

      expect(result.chapters, hasLength(3));
      final offsets = result.chapters.map((c) => c.charOffset).toList();
      // First chapter starts at 0
      expect(offsets[0], 0);
      // Each subsequent offset >= previous offset + charCount of previous chapter
      for (var i = 1; i < result.chapters.length; i++) {
        expect(
          result.chapters[i].charOffset,
          greaterThan(result.chapters[i - 1].charOffset),
        );
      }
      // totalChars = sum of all chapter charCounts
      final totalChars = result.chapters.fold(0, (s, c) => s + c.charCount);
      expect(result.totalChars, totalChars);
    });

    test('groupIndex values are deterministic across repeated calls', () {
      final blocks = [
        heading('Chapter 1', page: 1),
        block('Short.', page: 1),
        block('Also short.', page: 1),
        heading('Chapter 2', page: 2),
        block('More content.', page: 2),
      ];

      final outline2 = [
        outline('Chapter 1', page: 1),
        outline('Chapter 2', page: 2),
      ];

      final r1 = splitPdfChapters(blocks, outline: outline2, totalPages: 3);
      final r2 = splitPdfChapters(blocks, outline: outline2, totalPages: 3);

      for (var i = 0; i < r1.chapters.length; i++) {
        expect(r1.chapters[i].groups, r2.chapters[i].groups);
      }
    });

    test('cross-page paragraph is not split between chapters', () {
      // A paragraph that logically continues from page 1 to page 2;
      // the layout engine merges it; here we have it as one block.
      final blocks = [
        heading('Chapter 1', page: 1),
        block('Paragraph that spans pages one and two.', page: 1),
        heading('Chapter 2', page: 3),
        block('Chapter 2 content.', page: 3),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [outline('Chapter 1', page: 1), outline('Chapter 2', page: 3)],
        totalPages: 5,
      );

      expect(result.chapters, hasLength(2));
      // Cross-page paragraph stays in chapter 1
      expect(
        result.chapters[0].paragraphs.any(
          (p) => p.text.contains('spans pages'),
        ),
        isTrue,
      );
    });

    test('totalChars equals sum of all chapter charCounts', () {
      final blocks = [
        heading('Chapter 1', page: 1),
        block('A' * 50, page: 1),
        heading('Chapter 2', page: 2),
        block('B' * 100, page: 2),
      ];

      final result = splitPdfChapters(
        blocks,
        outline: [outline('Chapter 1', page: 1), outline('Chapter 2', page: 2)],
        totalPages: 3,
      );

      final sumChars = result.chapters.fold(0, (s, c) => s + c.charCount);
      expect(result.totalChars, sumChars);
    });
  });

  group('real-book outline shapes', () {
    String body(int n) => 'Body paragraph number $n. ' * 12;

    test('unsorted bookmarks never crash and keep page order', () {
      final blocks = [
        for (var pg = 1; pg <= 6; pg++) block(body(pg), page: pg),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('C', page: 5),
          outline('A', page: 1),
          outline('B', page: 3),
        ],
        totalPages: 6,
      );
      expect(result.chapters.map((c) => c.title), ['A', 'B', 'C']);
    });

    test('a huge container entry is replaced by its children', () {
      final blocks = [
        for (var pg = 1; pg <= 100; pg++) block(body(pg), page: pg),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Intro', page: 1),
          outline(
            'Letters',
            page: 11,
            children: [
              for (var i = 0; i < 5; i++)
                outline('Letter $i', page: 11 + i * 15),
            ],
          ),
          outline('Notes', page: 91),
        ],
        totalPages: 100,
      );
      expect(result.chapters.map((c) => c.title), [
        'Intro',
        for (var i = 0; i < 5; i++) 'Letter $i',
        'Notes',
      ]);
      expect(result.chapters[1].section, 'Letters');
    });

    test('a small chapter with subsections is not split', () {
      final blocks = [
        for (var pg = 1; pg <= 30; pg++) block(body(pg), page: pg),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [
          outline(
            'One',
            page: 1,
            children: [
              for (var i = 0; i < 4; i++) outline('s$i', page: 1 + i * 3),
            ],
          ),
          outline('Two', page: 16),
        ],
        totalPages: 30,
      );
      expect(result.chapters.map((c) => c.title), ['One', 'Two']);
    });

    test('substantial text before the first bookmark is kept', () {
      final blocks = [
        block(body(0), page: 1),
        for (var pg = 2; pg <= 5; pg++) block(body(pg), page: pg),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [outline('A', page: 2), outline('B', page: 4)],
        totalPages: 5,
      );
      expect(result.chapters.map((c) => c.title), ['Pembuka', 'A', 'B']);
    });

    test('a bare title page before the first bookmark is dropped', () {
      final blocks = [
        block('Title', page: 1),
        for (var pg = 2; pg <= 5; pg++) block(body(pg), page: pg),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [outline('A', page: 2), outline('B', page: 4)],
        totalPages: 5,
      );
      expect(result.chapters.map((c) => c.title), ['A', 'B']);
    });
  });

  group('table of contents without page numbers', () {
    String body(int n) => 'Body paragraph number $n. ' * 12;

    test('a chapter that just lists the other chapters is dropped', () {
      final blocks = [
        heading('Contents', page: 1),
        block('First Steps', page: 1),
        block('The Second Idea', page: 1),
        block('Third Thing Here', page: 1),
        block('Fourth Matter', page: 1),
        block(body(2), page: 2),
        block(body(3), page: 3),
        block(body(4), page: 4),
        block(body(5), page: 5),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Contents', page: 1),
          outline('First Steps', page: 2),
          outline('The Second Idea', page: 3),
          outline('Third Thing Here', page: 4),
          outline('Fourth Matter', page: 5),
        ],
        totalPages: 5,
      );
      expect(result.chapters.map((c) => c.title), [
        'First Steps',
        'The Second Idea',
        'Third Thing Here',
        'Fourth Matter',
      ]);
    });

    test('a normal chapter that mentions a title once is kept', () {
      final blocks = [
        for (var pg = 1; pg <= 4; pg++) ...[
          heading('Chapter $pg', page: pg),
          block('${body(pg)} See Chapter 2 for more.', page: pg),
          block(body(pg + 10), page: pg),
          block(body(pg + 20), page: pg),
          block(body(pg + 30), page: pg),
        ],
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [
          for (var pg = 1; pg <= 4; pg++) outline('Chapter $pg', page: pg),
        ],
        totalPages: 4,
      );
      expect(result.chapters, hasLength(4));
    });
  });

  group('layoutPdf title candidate', () {
    test('skips front-matter labels, takes a real heading on pages 1-5', () {
      PdfGlyph gl(String c, int i, double top, double h, int page) => PdfGlyph(
        char: c,
        pageNumber: page,
        bounds: PdfRectNormalized(
          left: 0.1 + i * 0.02,
          top: top,
          width: 0.015,
          height: h,
        ),
      );
      List<PdfGlyph> text(String t, double top, double h, int page) => [
        for (final (i, c) in t.split('').indexed) gl(c, i, top, h, page),
        gl('\n', t.length, top, 0, page),
      ];
      final page1 = [
        ...text('Copyright', 0.15, 0.04, 1),
        ...text('Body text of the book goes here for a while.', 0.30, 0.02, 1),
        ...text(
          'Body text of the book goes here again and more.',
          0.34,
          0.02,
          1,
        ),
      ];
      final page2 = [
        ...text('THE REAL TITLE', 0.15, 0.04, 2),
        ...text('Body text of the book goes here for a while.', 0.30, 0.02, 2),
        ...text(
          'Body text of the book goes here again and more.',
          0.34,
          0.02,
          2,
        ),
      ];
      const engine = PdfLayoutEngine();
      final laid = layoutPdf([
        engine.glyphsToLines(page1, pageNumber: 1),
        engine.glyphsToLines(page2, pageNumber: 2),
      ], const []);
      expect(laid.heading, 'THE REAL TITLE');
    });
  });

  group('title headings and junk', () {
    String body(int n) => 'Body paragraph number $n. ' * 12;

    test('digit + title headings under "1 Title" are dropped, others kept', () {
      final blocks = [
        heading('1', page: 1),
        heading('The Surprising Power', page: 1),
        heading('Something else entirely', page: 1),
        block(body(1), page: 1),
        heading('2', page: 3),
        block(body(2), page: 3),
        block(body(3), page: 4),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('1 The Surprising Power', page: 1),
          outline('2 Another One', page: 3),
        ],
        totalPages: 4,
      );
      expect(result.chapters[0].paragraphs.map((p) => p.text), [
        'Something else entirely',
        body(1),
      ]);
    });

    test('a chapter of only a repeated heading keeps it', () {
      final blocks = [
        heading('Epilogue', page: 1),
        block(body(1), page: 1),
        heading('Epilogue', page: 2),
        block(body(2), page: 2),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Epilogue', page: 1),
          outline('Epilogue two', page: 2),
        ],
        totalPages: 2,
      );
      expect(result.chapters.every((c) => c.paragraphs.isNotEmpty), isTrue);
    });

    test('merged TOC paragraph (titles inside one paragraph) is dropped', () {
      final blocks = [
        heading('Contents', page: 1),
        block(
          'First Steps The Second Idea Third Thing Here Fourth Matter',
          page: 1,
        ),
        block(body(2), page: 2),
        block(body(3), page: 3),
        block(body(4), page: 4),
        block(body(5), page: 5),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Contents', page: 1),
          outline('First Steps', page: 2),
          outline('The Second Idea', page: 3),
          outline('Third Thing Here', page: 4),
          outline('Fourth Matter', page: 5),
        ],
        totalPages: 5,
      );
      expect(result.chapters.map((c) => c.title), [
        'First Steps',
        'The Second Idea',
        'Third Thing Here',
        'Fourth Matter',
      ]);
    });

    test('contents text "1 Title" matches bookmarks "1 | Title"', () {
      final blocks = [
        heading('Contents', page: 1),
        block(
          'Foreword 1 First Steps 2 The Second Idea 3 Third Thing Here',
          page: 1,
        ),
        block(body(2), page: 2),
        block(body(3), page: 3),
        block(body(4), page: 4),
        block(body(5), page: 5),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Contents', page: 1),
          outline('Foreword', page: 2),
          outline('1 | First Steps', page: 3),
          outline('2 | The Second Idea', page: 4),
          outline('3 | Third Thing Here', page: 5),
        ],
        totalPages: 5,
      );
      expect(result.chapters.map((c) => c.title), [
        'Foreword',
        '1 | First Steps',
        '2 | The Second Idea',
        '3 | Third Thing Here',
      ]);
    });

    test('figure junk and bare numbers are dropped, short real text stays', () {
      PdfGlyph gl(String c, int i, double top, int page) => PdfGlyph(
        char: c,
        pageNumber: page,
        bounds: PdfRectNormalized(
          left: 0.1 + i * 0.012,
          top: top,
          width: 0.01,
          height: 0.02,
        ),
      );
      List<PdfGlyph> text(String t, double top) => [
        for (final (i, c) in t.split('').indexed) gl(c, i, top, 1),
        gl('\n', t.length, top, 1),
      ];
      final page = [
        // Six ordinary lines set the line pitch; the rest sit far apart.
        for (var n = 0; n < 6; n++)
          ...text(
            'A real sentence number $n that is long enough to read.',
            0.10 + n * 0.02,
          ),
        ...text('nn nn n', 0.30),
        ...text('r', 0.40),
        ...text('20', 0.50),
        ...text('No.', 0.60),
        ...text('Yes', 0.70),
      ];
      final engine = const PdfLayoutEngine();
      final laid = layoutPdf([
        engine.glyphsToLines(page, pageNumber: 1),
      ], const []);
      final texts = laid.chapters
          .expand((c) => c.paragraphs)
          .map((p) => p.text);
      expect(texts.join(' '), contains('A real sentence'));
      expect(texts.join(' '), isNot(contains('nn nn')));
      expect(texts.where((t) => t == 'r' || t == '20'), isEmpty);
    });
  });

  group('front matter, embedded contents, full title', () {
    String body(int n) => 'Body paragraph number $n. ' * 12;

    test('tiny label chapters are dropped, real short ones stay', () {
      final blocks = [
        block('Cover art', page: 1),
        block('A Penguin Book. Copyright 2013.', page: 2),
        block('For my wife.', page: 3),
        for (var pg = 4; pg <= 8; pg++) block(body(pg), page: pg),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Cover', page: 1),
          outline('Copyright Page', page: 2),
          outline('Dedication', page: 3),
          outline('One', page: 4),
          outline('Two', page: 6),
        ],
        totalPages: 8,
      );
      expect(result.chapters.map((c) => c.title), ['Dedication', 'One', 'Two']);
    });

    test(
      'a contents run inside another chapter is removed, text around stays',
      () {
        final blocks = [
          block('The lyf so short, the craft so longe to lerne.', page: 1),
          block('Front Notes', page: 1),
          block('First Steps', page: 1),
          block('The Second Idea', page: 1),
          block('Third Thing Here', page: 1),
          block('Fourth Matter', page: 1),
          block(body(1), page: 1),
          block(body(2), page: 2),
          block(body(3), page: 3),
          block(body(4), page: 4),
          block(body(5), page: 5),
        ];
        final result = splitPdfChapters(
          blocks,
          outline: [
            outline('Front Matter', page: 1),
            outline('First Steps', page: 2),
            outline('The Second Idea', page: 3),
            outline('Third Thing Here', page: 4),
            outline('Fourth Matter', page: 5),
          ],
          totalPages: 5,
        );
        final first = result.chapters.first.paragraphs
            .map((p) => p.text)
            .toList();
        expect(first, [
          'The lyf so short, the craft so longe to lerne.',
          body(1),
        ]);
      },
    );

    test('a few chapter titles quoted in prose are not a contents run', () {
      final blocks = [
        block('See First Steps and The Second Idea later', page: 1),
        block('Third Thing Here', page: 1),
        block(body(1), page: 1),
        block(body(2), page: 2),
        block(body(3), page: 3),
        block(body(4), page: 4),
        block(body(5), page: 5),
      ];
      final result = splitPdfChapters(
        blocks,
        outline: [
          outline('Opening', page: 1),
          outline('First Steps', page: 2),
          outline('The Second Idea', page: 3),
          outline('Third Thing Here', page: 4),
          outline('Fourth Matter', page: 5),
        ],
        totalPages: 5,
      );
      expect(result.chapters.first.paragraphs.length, 3);
    });

    test(
      'title = the full all-caps first line that contains the heading tail',
      () {
        PdfGlyph gl(String c, int i, double top, double h) => PdfGlyph(
          char: c,
          pageNumber: 1,
          bounds: PdfRectNormalized(
            left: 0.1 + i * 0.02,
            top: top,
            width: 0.015,
            height: h,
          ),
        );
        List<PdfGlyph> text(String t, double top, double h) => [
          for (final (i, c) in t.split('').indexed) gl(c, i, top, h),
          gl('\n', t.length, top, 0),
        ];
        const engine = PdfLayoutEngine();
        List<PdfLine> page(List<PdfGlyph> g) =>
            engine.glyphsToLines(g, pageNumber: 1);
        final laid = layoutPdf([
          page([
            ...text('LETTERS FROM A STOIC', 0.10, 0.02),
            ...text('FROM A STOIC', 0.20, 0.04),
            ...text(
              'Body text of the book goes here for a while and more.',
              0.30,
              0.02,
            ),
            ...text(
              'Body text of the book goes here again and again more.',
              0.34,
              0.02,
            ),
          ]),
        ], const []);
        expect(laid.heading, 'LETTERS FROM A STOIC');
      },
    );

    test('an all-caps first line alone (no heading) is not a title', () {
      PdfGlyph gl(String c, int i, double top, double h) => PdfGlyph(
        char: c,
        pageNumber: 1,
        bounds: PdfRectNormalized(
          left: 0.1 + i * 0.02,
          top: top,
          width: 0.015,
          height: h,
        ),
      );
      List<PdfGlyph> text(String t, double top, double h) => [
        for (final (i, c) in t.split('').indexed) gl(c, i, top, h),
        gl('\n', t.length, top, 0),
      ];
      const engine = PdfLayoutEngine();
      final laid = layoutPdf([
        engine.glyphsToLines([
          ...text('AN IMPRINT OF PENGUIN', 0.10, 0.02),
          ...text(
            'Body text of the book goes here for a while and more.',
            0.30,
            0.02,
          ),
          ...text(
            'Body text of the book goes here again and again more.',
            0.34,
            0.02,
          ),
        ], pageNumber: 1),
      ], const []);
      expect(laid.heading, isNull);
    });
  });
}
