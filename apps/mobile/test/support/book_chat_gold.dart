// Versioned evaluation data only; never used by application providers.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:luma/data/services/chapter_extractor.dart';
import 'package:luma/data/services/epub_parser.dart';
import 'package:luma/domain/luma_markdown.dart';
import 'package:luma/domain/models/book.dart';

import 'book_chat_spike.dart';

typedef SourceParagraph = ({
  String book,
  String chapter,
  int index,
  String text,
});

List<SourceParagraph> loadParagraphs({bool heldOut = false}) {
  final out = <SourceParagraph>[];
  final books = heldOut
      ? ['alice-in-wonderland', 'meditations']
      : ['enchiridion', 'pride-and-prejudice'];
  for (final book in books) {
    final parsed = extractChapters(
      parseEpub(File('test/fixtures/$book.epub').readAsBytesSync()),
    );
    for (final c in parsed.chapters) {
      for (final (i, p) in c.paragraphs.indexed) {
        if (p.type == ParagraphType.paragraph) {
          out.add((book: book, chapter: c.title, index: i, text: p.text));
        }
      }
    }
  }
  if (!heldOut) {
    final md = parseLumaMarkdown(
      File('test/fixtures/book_chat_partial.txt').readAsStringSync(),
    );
    for (final (i, p) in md.paragraphs.indexed) {
      if (p.type == ParagraphType.paragraph) {
        out.add((book: 'partial', chapter: '1', index: i, text: p.text));
      }
    }
  }
  return out;
}

typedef Evidence = ({
  String book,
  int revision,
  String chapter,
  int paragraph,
  int start,
  int end,
  String hash,
  String quote,
});
typedef GoldFact = ({String fact, List<Evidence> alternatives});
typedef GoldCase = ({
  String id,
  String status,
  List<GoldFact> facts,
  String audit,
});

List<GoldCase> readGold(String file) {
  final data =
      jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final c in data['cases'] as List)
      (
        id: c['id'] as String,
        status: c['expectedStatus'] as String,
        audit: c['audit'] as String,
        facts: [
          for (final f in c['facts'] as List)
            (
              fact: f['fact'] as String,
              alternatives: [
                for (final a in f['alternatives'] as List)
                  (
                    book: a['book'] as String,
                    revision: a['revision'] as int,
                    chapter: a['chapter'] as String,
                    paragraph: a['paragraph'] as int,
                    start: a['start'] as int,
                    end: a['end'] as int,
                    hash: a['paragraphHash'] as String,
                    quote: a['quote'] as String,
                  ),
              ],
            ),
        ],
      ),
  ];
}

SourceParagraph resolveEvidence(
  Evidence e,
  List<SourceParagraph> paragraphs,
  String book,
) {
  if (e.book != book || e.revision != 1 || e.start < 0 || e.end <= e.start) {
    throw const FormatException('evidence ownership/range');
  }
  final p = paragraphs
      .where(
        (p) =>
            p.book == book && p.chapter == e.chapter && p.index == e.paragraph,
      )
      .single;
  if (e.end > p.text.length ||
      textHash(p.text) != e.hash ||
      p.text.substring(e.start, e.end) != e.quote) {
    throw const FormatException('stale evidence');
  }
  return p;
}

/// Checks required evidence ranges independently of retrieval chunk IDs.
bool coversEvidence(Evidence e, SourceParagraph p, int from, int to) =>
    p.book == e.book &&
    e.revision == 1 &&
    p.chapter == e.chapter &&
    p.index == e.paragraph &&
    textHash(p.text) == e.hash &&
    e.start >= 0 &&
    e.end <= p.text.length &&
    e.end > e.start &&
    p.text.substring(e.start, e.end) == e.quote &&
    from <= e.start &&
    to >= e.end &&
    from >= 0 &&
    to <= p.text.length;

String verifyEvalManifest() {
  final file = File('test/fixtures/book_chat_eval_manifest.json');
  final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  for (final entry in (manifest['sha256'] as Map<String, dynamic>).entries) {
    final actual = sha256
        .convert(File('test/fixtures/${entry.key}').readAsBytesSync())
        .toString();
    if (actual != entry.value) {
      throw FormatException('frozen fixture changed: ${entry.key}');
    }
  }
  return sha256.convert(file.readAsBytesSync()).toString();
}
