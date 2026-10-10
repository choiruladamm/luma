import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/luma_markdown.dart';
import 'package:luma/domain/models/book.dart';

const _front = '''
---
luma: 1
book_key: atomic-habits
book: Atomic Habits
author: James Clear
chapter: 3
chapter_title: How to Build Better Habits
---

Paragraf pertama,
nyambung ke baris ini.

## Subjudul

Paragraf kedua.

***

Setelah pemisah.
''';

List<String> texts(ParsedMarkdown m) => [for (final p in m.paragraphs) p.text];

void main() {
  group('frontmatter', () {
    test('lengkap: meta dari header, body jadi paragraf + grup', () {
      final m = parseLumaMarkdown(_front, fileName: 'x.md');
      expect(m.complete, isTrue);
      expect(m.bookKey, 'atomic-habits');
      expect(m.book, 'Atomic Habits');
      expect(m.author, 'James Clear');
      expect(m.chapter, 3);
      expect(m.chapterTitle, 'How to Build Better Habits');
      expect(m.paragraphs.map((p) => p.type), [
        ParagraphType.paragraph,
        ParagraphType.heading,
        ParagraphType.paragraph,
        ParagraphType.sceneBreak,
        ParagraphType.paragraph,
      ]);
      expect(
        m.paragraphs.first.text,
        'Paragraf pertama, nyambung ke baris ini.',
      );
      expect(m.groups, [0, null, 1, null, 2]);
    });

    test('sebagian: gak complete, sisanya ditebak', () {
      final m = parseLumaMarkdown('---\nbook: Dune\n---\n\nIsi.');
      expect(m.complete, isFalse);
      expect(m.book, 'Dune');
      expect(m.bookKey, 'dune');
      expect(m.chapter, isNull);
    });

    test('book_key bukan slug → error', () {
      expect(
        () => parseLumaMarkdown('---\nbook_key: Atomic Habits\n---\n\nIsi.'),
        throwsA(
          isA<LumaMarkdownException>()
              .having((e) => e.error, 'error', LumaMarkdownError.badFrontmatter)
              .having((e) => e.detail, 'detail', 'book_key'),
        ),
      );
    });

    test('chapter bukan angka → error', () {
      expect(
        () => parseLumaMarkdown('---\nchapter: tiga\n---\n\nIsi.'),
        throwsA(
          isA<LumaMarkdownException>().having(
            (e) => e.detail,
            'detail',
            'chapter',
          ),
        ),
      );
    });

    test('--- di awal tanpa key:value = pemisah adegan, bukan frontmatter', () {
      final m = parseLumaMarkdown('---\n\nIsi pertama.\n\n---\n\nIsi kedua.');
      expect(m.paragraphs.map((p) => p.type), [
        ParagraphType.sceneBreak,
        ParagraphType.paragraph,
        ParagraphType.sceneBreak,
        ParagraphType.paragraph,
      ]);
    });
  });

  group('tanpa frontmatter: tebakan', () {
    test('judul dari # pertama, bab dari heading pertama', () {
      final m = parseLumaMarkdown(
        '# Atomic Habits\n\n## Bab Tiga\n\nIsi.',
        fileName: 'bab7.md',
      );
      expect(m.complete, isFalse);
      expect(m.book, 'Atomic Habits');
      expect(m.bookKey, 'atomic-habits');
      expect(m.chapterTitle, 'Atomic Habits');
      expect(m.chapter, 7);
    });

    test('gak ada heading: judul dari nama file, tanpa token bab', () {
      final m = parseLumaMarkdown('Isi.', fileName: 'atomic-habits-bab3.md');
      expect(m.book, 'Atomic Habits');
      expect(m.bookKey, 'atomic-habits');
      expect(m.chapter, 3);
      expect(m.chapterTitle, isNull);
    });

    test('bab di depan nama file: bab beda, buku sama', () {
      for (final (f, n) in [
        ('bab-1-deep-work.md', 1),
        ('Chapter_02_Deep_Work.md', 2),
      ]) {
        final m = parseLumaMarkdown('Isi.', fileName: f);
        expect((m.book, m.bookKey, m.chapter), ('Deep Work', 'deep-work', n));
      }
    });

    test('nama file cuma token bab: balik ke nama file utuh', () {
      final m = parseLumaMarkdown('Isi.', fileName: 'bab-3.md');
      expect((m.book, m.chapter), ('Bab 3', 3));
    });

    test('"ch" di tengah kata bukan nomor bab', () {
      final m = parseLumaMarkdown('Isi.', fileName: 'catch-22.md');
      expect((m.book, m.chapter), ('Catch 22', null));
    });

    test('nomor bab dari nama file', () {
      int? n(String f) => parseLumaMarkdown('Isi.', fileName: f).chapter;
      expect(n('chapter-07.md'), 7);
      expect(n('Ch12.md'), 12);
      expect(n('catatan.md'), isNull);
    });

    test('gak ada heading dan gak ada nama file: semua null', () {
      final m = parseLumaMarkdown('Isi.');
      expect(m.book, isNull);
      expect(m.bookKey, isNull);
      expect(m.chapter, isNull);
    });
  });

  group('body toleran (gaya Marker)', () {
    test(
      'gambar, tabel, kode dibuang; link, list, kutipan, inline disisain',
      () {
        final m = parseLumaMarkdown('''
# Judul

![fig](x.png)

| a | b |
|---|---|
| 1 | 2 |

```
kode
```

Baca [di sini](http://x.y) soal **tebal** dan *miring* dan `kode`.

- satu
- dua

> kutipan
> lanjut
''');
        expect(texts(m), [
          'Judul',
          'Baca di sini soal tebal dan miring dan kode.',
          'satu',
          'dua',
          'kutipan lanjut',
        ]);
      },
    );

    test('heading level apa aja, --- dan * * * jadi pemisah', () {
      final m = parseLumaMarkdown('###### Kecil\n\nIsi.\n\n* * *\n\nLagi.');
      expect(m.paragraphs.map((p) => p.type), [
        ParagraphType.heading,
        ParagraphType.paragraph,
        ParagraphType.sceneBreak,
        ParagraphType.paragraph,
      ]);
    });

    test('CRLF sama kayak LF', () {
      expect(
        texts(parseLumaMarkdown('A\r\nb\r\n\r\nC')),
        texts(parseLumaMarkdown('A\nb\n\nC')),
      );
    });
  });

  group('kosong', () {
    for (final s in [
      '',
      '\n\n',
      '# Cuma heading',
      '![x](y.png)',
      '---\nbook: A\n---\n',
    ]) {
      test('"${s.replaceAll('\n', r'\n')}" → error empty', () {
        expect(
          () => parseLumaMarkdown(s),
          throwsA(
            isA<LumaMarkdownException>().having(
              (e) => e.error,
              'error',
              LumaMarkdownError.empty,
            ),
          ),
        );
      });
    }
  });

  test('slugify', () {
    expect(slugify('Atomic Habits!'), 'atomic-habits');
    expect(slugify('  --A_b  '), 'a-b');
    expect(slugify('日本'), '');
  });
}
