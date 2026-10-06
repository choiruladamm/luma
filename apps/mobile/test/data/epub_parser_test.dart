import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/epub_parser.dart';

import '../epub.dart';

Matcher throwsEpub(EpubError e) =>
    throwsA(isA<EpubException>().having((x) => x.error, 'error', e));

void main() {
  test('Pride and Prejudice (Gutenberg, EPUB2 + NCX)', () async {
    final bytes = File('test/fixtures/pride-and-prejudice.epub')
        .readAsBytesSync();
    // Runs in an isolate: the outline must be plain, sendable data.
    final book = await Isolate.run(() => parseEpub(bytes));

    expect(book.title, 'Pride and Prejudice');
    expect(book.author, 'Jane Austen');
    expect(book.cover?.extension, 'jpg');
    expect(book.cover!.bytes.take(2), [0xFF, 0xD8]); // JPEG magic

    expect(book.chapters.length, 63);
    expect(book.chapters[1].title, 'Chapter I.');
    expect(book.chapters[61].title, contains('CHAPTER LXI'));
    // Gutenberg's licence is in the TOC too; dropping non-content is #9's job.
    expect(book.chapters.last.title, contains('PROJECT GUTENBERG'));

    // Chapters tile the text: each one ends where the next one starts.
    for (var i = 0; i + 1 < book.chapters.length; i++) {
      final (a, b) = (book.chapters[i], book.chapters[i + 1]);
      expect(a.endAnchor, b.startAnchor, reason: a.title);
      expect(a.files.last, b.files.first, reason: a.title);
    }
    for (final c in book.chapters) {
      expect(c.files.every(book.html.containsKey), isTrue);
    }
  });

  test('EPUB3 nav in a subfolder, chapter spanning files, cover-image', () {
    final book = parseEpub(
      buildEpub(
        {
          'OEBPS/content.opf': opf(
            metadata:
                '<dc:title> The  Republic </dc:title>'
                '<dc:creator>Plato</dc:creator><dc:creator>Jowett</dc:creator>',
            manifest:
                '<item id="nav" href="nav/nav.xhtml" properties="nav scripted" '
                'media-type="application/xhtml+xml"/>'
                '<item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>'
                '<item id="c1b" href="text/ch1b.xhtml" media-type="application/xhtml+xml"/>'
                '<item id="c2" href="text/ch%202.xhtml" media-type="application/xhtml+xml"/>'
                '<item id="img" href="img/cover.png" properties="cover-image" '
                'media-type="image/png"/>',
            spine: '<itemref idref="c1"/><itemref idref="c1b"/><itemref idref="c2"/>',
          ),
          'OEBPS/nav/nav.xhtml': xhtml(
            '<nav xmlns:epub="http://www.idpf.org/2007/ops" epub:type="landmarks">'
            '<ol><li><a href="../text/ch1.xhtml">Start</a></li></ol></nav>'
            '<nav xmlns:epub="http://www.idpf.org/2007/ops" epub:type="toc"><ol>'
            '<li><a href="../text/ch1.xhtml">Book I</a></li>'
            '<li><a href="../text/ch%202.xhtml#a">Book II</a><ol>'
            '<li><a href="../text/ch%202.xhtml#b"> Part  2 </a></li></ol></li>'
            '<li><a href="../text/missing.xhtml">Gone</a></li>'
            '</ol></nav>',
          ),
          'OEBPS/text/ch1.xhtml': xhtml('<p>one</p>'),
          'OEBPS/text/ch1b.xhtml': xhtml('<p>one, continued</p>'),
          'OEBPS/text/ch 2.xhtml': xhtml(
            '<p id="a">two</p><p id="b">three</p>',
          ),
        },
        binary: {
          'OEBPS/img/cover.png': [0x89, 0x50, 0x4E, 0x47],
        },
      ),
    );

    expect(book.title, 'The Republic');
    expect(book.author, 'Plato, Jowett');
    expect(book.cover?.extension, 'png');
    expect(
      // Records compare lists by identity, so files are joined.
      book.chapters.map(
        (c) => (c.title, c.files.join(' | '), c.startAnchor, c.endAnchor),
      ),
      [
        // Book I runs on into ch1b (not in the TOC) and the head of ch 2.
        (
          'Book I',
          'OEBPS/text/ch1.xhtml | OEBPS/text/ch1b.xhtml | OEBPS/text/ch 2.xhtml',
          null,
          'a',
        ),
        ('Book II', 'OEBPS/text/ch 2.xhtml', 'a', 'b'),
        ('Part 2', 'OEBPS/text/ch 2.xhtml', 'b', null),
      ],
    );
    expect(book.html['OEBPS/text/ch1b.xhtml'], contains('one, continued'));
  });

  test('EPUB2 NCX with nested navPoints and meta cover', () {
    final book = parseEpub(
      buildEpub(
        {
          'OEBPS/content.opf': opf(
            metadata:
                '<dc:title>Walden</dc:title><meta name="cover" content="cov"/>',
            manifest:
                '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
                '<item id="a" href="a.html" media-type="application/xhtml+xml"/>'
                '<item id="b" href="b.html" media-type="application/xhtml+xml"/>'
                '<item id="cov" href="cover.jpg" media-type="image/jpeg"/>',
            spine: '<itemref idref="a"/><itemref idref="b"/>',
            spineAttrs: 'toc="ncx"',
          ),
          'OEBPS/toc.ncx':
              '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">'
              '<navMap><navPoint><navLabel><text>Economy</text></navLabel>'
              '<content src="a.html"/>'
              '<navPoint><navLabel><text>Sounds</text></navLabel>'
              '<content src="b.html"/></navPoint></navPoint></navMap>'
              '<pageList><pageTarget><navLabel><text>{1}</text></navLabel>'
              '<content src="a.html#p1"/></pageTarget></pageList></ncx>',
          'OEBPS/a.html': xhtml('<p>a</p>'),
          'OEBPS/b.html': xhtml('<p>b</p>'),
        },
        binary: {
          'OEBPS/cover.jpg': [0xFF, 0xD8],
        },
      ),
    );
    expect(book.author, isNull);
    expect(book.cover?.extension, 'jpg');
    expect(book.chapters.map((c) => (c.title, c.files.single)), [
      ('Economy', 'OEBPS/a.html'),
      ('Sounds', 'OEBPS/b.html'),
    ]);
  });

  test('no TOC: one chapter per spine file, titled "Bab N"', () {
    final book = parseEpub(
      buildEpub({
        'OEBPS/content.opf': opf(
          manifest:
              '<item id="a" href="a.html" media-type="application/xhtml+xml"/>'
              '<item id="b" href="b.html" media-type="application/xhtml+xml"/>',
          spine: '<itemref idref="a"/><itemref idref="b"/>',
        ),
        'OEBPS/a.html': xhtml(''),
        'OEBPS/b.html': xhtml(''),
      }),
    );
    expect(book.title, isNull);
    expect(book.cover, isNull);
    expect(book.chapters.map((c) => c.title), ['Bab 1', 'Bab 2']);
  });

  group('errors', () {
    String minimalOpf() => opf(
      manifest:
          '<item id="a" href="a.html" media-type="application/xhtml+xml"/>',
      spine: '<itemref idref="a"/>',
    );

    test('not a zip → notEpub; a truncated EPUB → corrupt', () {
      expect(
        () => parseEpub(Uint8List.fromList([1, 2, 3])),
        throwsEpub(EpubError.notEpub),
      );
      final epub = File('test/fixtures/pride-and-prejudice.epub')
          .readAsBytesSync();
      expect(
        () => parseEpub(Uint8List.sublistView(epub, 0, epub.length ~/ 2)),
        throwsEpub(EpubError.corrupt),
      );
    });

    test('zip without container.xml → notEpub', () {
      expect(
        () => parseEpub(buildEpub({'a.txt': 'hi'}, container: false)),
        throwsEpub(EpubError.notEpub),
      );
    });

    test('container pointing at a missing OPF → corrupt', () {
      expect(() => parseEpub(buildEpub({})), throwsEpub(EpubError.corrupt));
    });

    test('Adobe rights.xml or FairPlay sinf.xml → drm', () {
      for (final f in ['META-INF/rights.xml', 'META-INF/sinf.xml']) {
        expect(
          () => parseEpub(
            buildEpub({'OEBPS/content.opf': minimalOpf(), f: '<x/>'}),
          ),
          throwsEpub(EpubError.drm),
          reason: f,
        );
      }
    });

    String encryption(String algorithm) =>
        '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
        'xmlns:enc="http://www.w3.org/2001/04/xmlenc#"><enc:EncryptedData>'
        '<enc:EncryptionMethod Algorithm="$algorithm"/></enc:EncryptedData>'
        '</encryption>';

    test('font obfuscation is fine, real encryption is drm', () {
      Uint8List withAlgo(String a) => buildEpub({
        'OEBPS/content.opf': minimalOpf(),
        'OEBPS/a.html': xhtml(''),
        'META-INF/encryption.xml': encryption(a),
      });
      expect(
        parseEpub(withAlgo('http://www.idpf.org/2008/embedding')).chapters,
        hasLength(1),
      );
      expect(
        () =>
            parseEpub(withAlgo('http://www.w3.org/2001/04/xmlenc#aes128-cbc')),
        throwsEpub(EpubError.drm),
      );
    });
  });
}
