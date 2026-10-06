import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/chapter_extractor.dart';
import 'package:luma/data/services/epub_parser.dart';

import '../epub.dart';

/// Extracts [chapters] over in-memory [files] (path → body HTML).
List<ParsedChapter> extract(
  Map<String, String> files,
  List<ChapterSource> chapters,
) => extractChapters(
  EpubOutline(
    title: null,
    author: null,
    cover: null,
    chapters: chapters,
    html: files.map((k, v) => MapEntry(k, xhtml(v))),
  ),
).chapters;

ChapterSource ch(
  String title,
  List<String> files, {
  String? start,
  String? end,
}) => ChapterSource(
  title: title,
  files: files,
  startAnchor: start,
  endAnchor: end,
);

List<(String, String)> blocks(ParsedChapter c) => [
  for (final p in c.paragraphs) (p.type.name, p.text),
];

void main() {
  test('blocks: headings, paragraphs, loose div text, list items, <br>', () {
    final [c] = extract(
      {
        'a':
            '<h2>Chapter\n   One</h2>'
            '<div>Loose  text\n in a div<p>A real\n paragraph.</p>tail</div>'
            '<ul><li>first</li><li>second</li></ul>'
            '<p class="poem">Conduct me, Zeus,<br/>Wherever your&#160;decrees</p>',
      },
      [
        ch('One', ['a']),
      ],
    );
    expect(blocks(c), [
      ('heading', 'Chapter One'),
      ('paragraph', 'Loose text in a div'),
      ('paragraph', 'A real paragraph.'),
      ('paragraph', 'tail'),
      ('paragraph', 'first'),
      ('paragraph', 'second'),
      ('paragraph', 'Conduct me, Zeus,\nWherever your decrees'),
    ]);
  });

  test('scene breaks: <hr>, asterisks, ⁂; doubles and tail dropped', () {
    final [c] = extract(
      {'a': '<p>one</p><hr/><p>* * *</p><p>two</p><p>⁂</p><p>three</p><hr/>'},
      [
        ch('X', ['a']),
      ],
    );
    expect(blocks(c), [
      ('paragraph', 'one'),
      ('sceneBreak', '***'),
      ('paragraph', 'two'),
      ('sceneBreak', '***'),
      ('paragraph', 'three'),
    ]);
  });

  test('anchors cut chapters mid-file and across files', () {
    final files = {
      'a': '<p>front matter</p><div id="c1"><h3>I</h3><p>first</p></div>',
      'b':
          '<p>first, continued</p><p>more <a id="c2"/>II starts here</p>'
          '<p>second</p>',
    };
    final chapters = extract(files, [
      ch('I', ['a', 'b'], start: 'c1', end: 'c2'),
      ch('II', ['b'], start: 'c2'),
    ]);
    expect(blocks(chapters[0]), [
      ('heading', 'I'),
      ('paragraph', 'first'),
      ('paragraph', 'first, continued'),
      ('paragraph', 'more'),
    ]);
    expect(blocks(chapters[1]), [
      ('paragraph', 'II starts here'),
      ('paragraph', 'second'),
    ]);
  });

  test('page numbers, footnote marks, captions and figures are dropped', () {
    final [c] = extract(
      {
        'a':
            '<h2><span class="caption">“She did not listen.”</span><br/>'
            'CHAPTER LII.</h2>'
            '<p>Text<span class="x-ebookmaker-pageno" title="{4}">[4]</span> '
            'goes on<a href="#fn1" class="pginternal">[1]</a> and on<sup>2</sup>.</p>'
            '<div class="figcenter"><p>Illustration</p></div>'
            '<figure><figcaption>Fig. 1</figcaption></figure>',
      },
      [
        ch('“She did not listen.” CHAPTER LII.', ['a']),
      ],
    );
    expect(blocks(c), [
      ('heading', 'CHAPTER LII.'),
      ('paragraph', 'Text goes on and on.'),
    ]);
    // A TOC label polluted by the caption falls back to the heading.
    expect(c.title, 'CHAPTER LII.');
  });

  test('footnote marks are cleaned out of titles', () {
    final [c] = extract(
      {'a': '<h3>XXIX</h3><p>text</p>'},
      [
        ch('XXIX[2]', ['a']),
      ],
    );
    expect(c.title, 'XXIX');
  });

  test('non-content chapters are dropped', () {
    final chapters = extract(
      {
        'toc':
            '<h2>CONTENTS</h2>'
            '<p><a href="a#1">The First Book</a></p>'
            '<p><a href="a#2">The Second Book</a></p>',
        'title': '<h1>MEDITATIONS</h1>',
        'a':
            '<h2>THE FIRST BOOK</h2><p>Of my grandfather Verus…</p>'
            '<footer id="pg-footer"><h2 id="lic">LICENSE</h2><p>terms</p></footer>',
      },
      [
        ch('CONTENTS', ['toc']),
        ch('MEDITATIONS', ['title']),
        ch('THE FIRST BOOK', ['a'], end: 'lic'),
        // Starts inside the skipped Gutenberg footer: nothing to read.
        ch('LICENSE', ['a'], start: 'lic'),
      ],
    );
    expect(chapters.map((c) => c.title), ['THE FIRST BOOK']);
  });

  test('a start anchor that does not exist reads the whole file', () {
    final [c] = extract(
      {'a': '<p>everything</p>'},
      [
        ch('X', ['a'], start: 'nope'),
      ],
    );
    expect(blocks(c), [('paragraph', 'everything')]);
  });

  test('groups and char offsets', () {
    final result = extractChapters(
      EpubOutline(
        title: null,
        author: null,
        cover: null,
        chapters: [
          ch('A', ['a']),
          ch('B', ['b']),
        ],
        html: {
          'a': xhtml('<h3>A</h3><p>${'x' * 100}</p><p>${'y' * 100}</p>'),
          'b': xhtml('<p>${'z' * 500}</p>'),
        },
      ),
    );
    final [a, b] = result.chapters;
    expect(a.groups, [null, 0, 0]);
    expect(b.groups, [0]);
    expect(a.charOffset, 0);
    expect(b.charOffset, 1 + 200);
    expect(result.totalChars, 201 + 500);
  });

  group('real books', () {
    ParsedChapter named(List<ParsedChapter> cs, String t) =>
        cs.firstWhere((c) => c.title == t);

    test('Pride and Prejudice', () {
      final book = extractChapters(
        parseEpub(
          File('test/fixtures/pride-and-prejudice.epub').readAsBytesSync(),
        ),
      );
      final titles = book.chapters.map((c) => c.title).toList();
      expect(titles, hasLength(62)); // licence dropped
      expect(titles.last, 'CHAPTER LXI.');
      expect(titles, contains('CHAPTER II.')); // caption stripped
      final first = named(book.chapters, 'CHAPTER LXI.').paragraphs[1].text;
      expect(first, startsWith('HAPPY for all her maternal feelings'));
      expect(first, isNot(contains('\n'))); // source line wraps are spaces
      expect(
        book.totalChars,
        book.chapters.last.charOffset + book.chapters.last.charCount,
      );
    });

    test('The Enchiridion', () {
      final book = extractChapters(
        parseEpub(File('test/fixtures/enchiridion.epub').readAsBytesSync()),
      );
      final titles = book.chapters.map((c) => c.title).toList();
      expect(titles, isNot(contains('CONTENTS')));
      expect(titles, contains('XXIX'));
      expect(titles, isNot(contains(matches('PROJECT GUTENBERG'))));
      expect(
        named(book.chapters, 'I').paragraphs[1].text,
        startsWith('There are things which are within our power'),
      );
    });
  });
}
