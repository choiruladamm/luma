// Frozen final-evaluation pipeline. Gold labels never enter these inputs.
import 'dart:convert';
import 'dart:io';

import 'package:luma/data/services/epub_parser.dart';

import 'book_chat_gold.dart';
import 'book_chat_oracle.dart';
import 'book_chat_retrieval.dart';
import 'book_chat_spike.dart';

const heldoutEmbeddingModel = 'qwen/qwen3-embedding-8b';
const heldoutAnswerModel = 'deepseek/deepseek-v4.1-flash';
const heldoutQueryPrefix =
    'Instruct: Given a question about a book, retrieve passages from that book that answer the question.\nQuery: ';

typedef HeldoutInput = ({EvalCase input, Evidence? selection});

List<HeldoutInput> heldoutInputs() {
  final document = jsonDecode(
    File('test/fixtures/book_chat_held_out_v1.json').readAsStringSync(),
  ) as Map;
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

List<RetrievalChunk> heldoutChunks(List<SourceParagraph> paragraphs) => [
  for (final group in groupedChunks(loadCorpus(heldOut: true), paragraphs))
    if (group.passage.text.length <= 1800)
      group
    else
      ...windowChunks(
        group.ranges.map((r) => r.paragraph).toList(),
        size: 1800,
        overlap: 200,
      ),
];

String heldoutQuery(EvalCase c, List<RetrievalChunk> chunks) =>
    heldoutQueryPrefix +
    [
      for (final h in caseHistory(c)) 'Q: ${h.question}\nA: ${h.answer}',
      c.question,
      if (c.quote != null)
        chunks
            .firstWhere((s) => s.passage.id == selectedWindow(c, chunks))
            .passage
            .text,
    ].join('\n');

String heldoutUser(
  HeldoutInput c,
  List<Passage> sources,
  List<SourceParagraph> paragraphs,
) {
  final selected = sources.indexWhere(
    (p) =>
        p.id ==
        selectedWindow(c.input, [
          for (final p in sources) (passage: p, ranges: <SourceRange>[]),
        ]),
  );
  if (c.selection != null) {
    resolveEvidence(c.selection!, paragraphs, c.input.book);
    if (selected < 0 || !sources[selected].text.contains(c.selection!.quote)) {
      throw const FormatException(
        'selected quote absent from retrieved source',
      );
    }
  }
  final outline = parseEpub(
    File('test/fixtures/${c.input.book}.epub').readAsBytesSync(),
  );
  final prompt = jsonEncode({
    'book': {
      'title': outline.title ?? c.input.book,
      'author': outline.author ?? '',
    },
    'question': c.input.question,
    'history': [
      for (final h in caseHistory(c.input))
        {'question': h.question, 'answer': h.answer},
    ],
    if (c.selection != null) 'selectedSourceId': 'S${selected + 1}',
    if (c.selection != null) 'selectedQuote': c.selection!.quote,
    'sources': [
      for (final (i, p) in sources.indexed)
        {'id': 'S${i + 1}', 'chapter': p.chapter, 'text': p.text},
    ],
  });
  if (bytes(c.input.question) > questionBudget ||
      bytes(prompt) + bytes(oracleJsonSystem) > promptBudget) {
    throw const FormatException('held-out prompt budget');
  }
  return prompt;
}

double? referencedRangeRecall(
  GoldCase gold,
  List<Claim> claims,
  List<RetrievalChunk> sources,
) {
  final used = {
    for (final c in claims)
      for (final ref in c.sources) int.parse(ref.id.substring(1)) - 1,
  };
  return rangeRecall(gold, [for (final i in used) sources[i]]);
}

String verifyHeldoutProtocol() {
  verifyEvalManifest();
  final file = File('test/fixtures/book_chat_heldout_protocol_v1.json');
  final data = jsonDecode(file.readAsStringSync()) as Map;
  for (final entry in (data['sourceHashes'] as Map).entries) {
    if (textHash(File(entry.key as String).readAsStringSync()) != entry.value) {
      throw FormatException('frozen pipeline changed: ${entry.key}');
    }
  }
  if (data['answerSystemHash'] != textHash(oracleJsonSystem) ||
      data['embeddingModel'] != heldoutEmbeddingModel ||
      data['answerModel'] != heldoutAnswerModel) {
    throw const FormatException('frozen protocol mismatch');
  }
  return textHash(file.readAsStringSync());
}
