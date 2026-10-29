import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final corpusFile = File('test/fixtures/book_chat_discussion_cases.json');
  final corpus = jsonDecode(corpusFile.readAsStringSync()) as Map;
  final protocol = jsonDecode(
    File('test/fixtures/book_chat_discussion_protocol.json').readAsStringSync(),
  ) as Map;
  final books = corpus['books'] as List;
  final cases = corpus['cases'] as List;

  test('discussion corpus matches frozen bytes and book-disjoint splits', () {
    expect(
      sha256.convert(corpusFile.readAsBytesSync()).toString(),
      protocol['corpusSha256'],
    );
    expect(books.map((b) => b['id']).toSet(), hasLength(books.length));
    expect(cases.map((c) => c['id']).toSet(), hasLength(cases.length));
    for (final split in ['development', 'validation']) {
      final rows = cases.where((c) => c['split'] == split).toList();
      expect(rows, hasLength(protocol['corpusCounts'][split] as int));
      expect(rows.map((c) => c['category']).toSet(), {
        'fact',
        'cross_chapter',
        'global',
        'interpretation',
        'application',
        'external_comparison',
        'missing_detail',
        'false_premise',
        'clarification',
        'contextual_followup',
        'correction',
        'off_topic',
        'critique',
        'injection',
      });
      for (final row in rows) {
        final book = books.singleWhere((b) => b['id'] == row['book']);
        expect(book['split'], split);
      }
    }
  });

  test('gold resolves to exact original paragraphs in the active book', () {
    for (final row in cases) {
      final book = books.singleWhere((b) => b['id'] == row['book']);
      final chapters = book['chapters'] as List;
      final input = row['input'] as Map;
      final gold = row['gold'] as Map;
      expect((input['question'] as String).trim(), isNotEmpty);
      expect(
        input.keys.toSet().difference({'question', 'history', 'selectedQuote'}),
        isEmpty,
      );
      expect(gold['expectations'], isNotEmpty);
      for (final evidence in gold['evidence'] as List) {
        final chapter = chapters.singleWhere(
          (c) => c['id'] == evidence['chapter'],
        );
        final paragraphs = chapter['paragraphs'] as List;
        expect(
          evidence['paragraph'],
          inInclusiveRange(0, paragraphs.length - 1),
        );
        expect(paragraphs[evidence['paragraph'] as int], evidence['excerpt']);
      }
      if (row['category'] == 'global') {
        expect(
          (gold['evidence'] as List).map((e) => e['chapter']).toSet(),
          chapters.map((c) => c['id']).toSet(),
        );
      }
      if (row['category'] == 'contextual_followup' ||
          row['category'] == 'correction') {
        expect(input['history'], isNotEmpty);
      }
    }
  });
}
