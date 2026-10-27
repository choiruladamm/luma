// Fresh book-level validation inputs; no generation output is used for labels.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:luma/data/services/chapter_extractor.dart';
import 'package:luma/data/services/epub_parser.dart';
import 'package:luma/domain/models/book.dart';

import 'book_chat_gold.dart';
import 'book_chat_heldout.dart';
import 'book_chat_retrieval.dart';
import 'book_chat_spike.dart';

const validation3File = 'test/fixtures/book_chat_validation3_cases.json';
const validation3Books = ['a-christmas-carol', 'sherlock-holmes'];

({
  List<SourceParagraph> paragraphs,
  List<RetrievalChunk> chunks,
  Map<String, Map<String, String>> metadata,
})
validation3Corpus() {
  final paragraphs = <SourceParagraph>[];
  final corpus = <Passage>[];
  final metadata = <String, Map<String, String>>{};
  for (final book in validation3Books) {
    final outline = parseEpub(
      File('test/fixtures/$book.epub').readAsBytesSync(),
    );
    metadata[book] = {
      'title': outline.title ?? book,
      'author': outline.author ?? '',
    };
    for (final c in extractChapters(outline).chapters) {
      for (final (i, p) in c.paragraphs.indexed) {
        if (p.type == ParagraphType.paragraph) {
          paragraphs.add((
            book: book,
            chapter: c.title,
            index: i,
            text: p.text,
          ));
        }
      }
      corpus.addAll(passages(book, c.title, c.paragraphs, c.groups));
    }
  }
  final chunks = [
    for (final g in groupedChunks(corpus, paragraphs))
      if (g.passage.text.length <= 1800)
        g
      else
        ...windowChunks(
          g.ranges.map((r) => r.paragraph).toList(),
          size: 1800,
          overlap: 200,
        ),
  ];
  return (paragraphs: paragraphs, chunks: chunks, metadata: metadata);
}

List<HeldoutInput> validation3Inputs() {
  final document = jsonDecode(File(validation3File).readAsStringSync()) as Map;
  return [
    for (final row in document['cases'] as List)
      (
        input: (
          id: row['id'] as String,
          book: row['book'] as String,
          question: row['question'] as String,
          expected: <List<String>>[],
          reason: '',
          history: ((row['history'] ?? []) as List)
              .cast<Map<String, dynamic>>(),
          quote: row['selectedQuote'] == null
              ? null
              : '${row['book']}:${row['selectedQuote']['chapter']}:${row['selectedQuote']['paragraph']}-${row['selectedQuote']['paragraph']}',
        ),
        selection: row['selectedQuote'] == null
            ? null
            : (
                book: row['selectedQuote']['book'] as String,
                revision: row['selectedQuote']['revision'] as int,
                chapter: row['selectedQuote']['chapter'] as String,
                paragraph: row['selectedQuote']['paragraph'] as int,
                start: row['selectedQuote']['start'] as int,
                end: row['selectedQuote']['end'] as int,
                hash: row['selectedQuote']['paragraphHash'] as String,
                quote: row['selectedQuote']['quote'] as String,
              ),
      ),
  ];
}

String verifyValidation3() {
  final file = File('test/fixtures/book_chat_validation3_protocol.json');
  final data = jsonDecode(file.readAsStringSync()) as Map;
  for (final entry in (data['sha256'] as Map).entries) {
    if (textHash(File(entry.key as String).readAsStringSync()) != entry.value) {
      throw FormatException('fresh validation source changed: ${entry.key}');
    }
  }
  for (final entry in (data['binarySha256'] as Map).entries) {
    final actual = sha256
        .convert(File(entry.key as String).readAsBytesSync())
        .toString();
    if (actual != entry.value) {
      throw FormatException('fresh validation book changed: ${entry.key}');
    }
  }
  return textHash(file.readAsStringSync());
}
