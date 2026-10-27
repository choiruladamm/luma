import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_gold.dart';
import '../support/book_chat_validation3.dart';

void main() {
  test('validation3 source dump only (no model or labels)', () {
    final data = validation3Corpus();
    File('/tmp/luma-validation3-paragraphs.json').writeAsStringSync(
      jsonEncode([
        for (final p in data.paragraphs)
          {
            'book': p.book,
            'chapter': p.chapter,
            'paragraph': p.index,
            'text': p.text,
          },
      ]),
    );
    expect(data.paragraphs, isNotEmpty);
  }, skip: Platform.environment['BOOK_CHAT_SOURCE_DUMP'] != '1');
  test('validation3 frozen labels resolve in separate books', () {
    final protocol = verifyValidation3();
    final data = validation3Corpus();
    final gold = readGold(validation3File);
    final inputs = validation3Inputs();
    expect(gold.length, 40);
    expect(inputs.map((c) => c.input.id).toSet().length, 40);
    expect(gold.where((g) => g.facts.isNotEmpty).length, 30);
    for (final g in gold) {
      for (final f in g.facts) {
        expect(f.alternatives, isNotEmpty);
        for (final e in f.alternatives) {
          resolveEvidence(e, data.paragraphs, e.book);
        }
      }
    }
    expect(verifyValidation3(), protocol);
  });
}
