import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_refinement.dart';
import '../support/book_chat_spike.dart';

void main() {
  final c = readCases().first;
  Passage source(String id) => (
    id: id,
    book: c.book,
    revision: 1,
    chapter: '1',
    from: 0,
    to: 0,
    text: 'Real evidence $id',
    hash: textHash('Real evidence $id'),
  );
  test('selection validates indices, pins selected source and respects byte budget', () {
    final sources = [source('a'), source('b')];
    expect(parseSelection('{"selected":[2,1]}', sources).map((p) => p.id), [
      'b',
      'a',
    ]);
    expect(parseSelection('{"selected":[]}', sources, quoteId: 'a'), [
      sources.first,
    ]);
    for (final bad in [
      '{"selected":[1,1]}',
      '{"selected":[0]}',
      '{"selected":[3]}',
      '{"selected":["1"]}',
      '{}',
    ]) {
      expect(() => parseSelection(bad, sources), throwsFormatException);
    }
    final data = jsonDecode(rerankUser(c, sources, quoteId: 'a')) as Map;
    expect(data['selectedSourceId'], 1);
    expect(data.containsKey('facts'), isFalse);
    expect(data['candidates'][0]['text'], sources.first.text);
    final foreign = (
      id: 'x',
      book: 'other',
      revision: 1,
      chapter: '1',
      from: 0,
      to: 0,
      text: 'x',
      hash: textHash('x'),
    );
    expect(() => rerankUser(c, [foreign]), throwsFormatException);
  });
  test('focused parser retains citation checks and replaces unsafe notes deterministically', () {
    final sources = [source('a')];
    String raw(String status, List<Object> claims) => jsonEncode({
      'status': status,
      'claims': claims,
      'note': 'Invented habit or unrelated book fact',
    });
    final claim = {
      'text': 'Supported',
      'source_ids': ['S1'],
    };
    expect(
      parseFocusedAnswer(raw('not_found', []), sources, c.book).note,
      missingEvidenceNote,
    );
    expect(
      parseFocusedAnswer(raw('partial', [claim]), sources, c.book).note,
      partialEvidenceNote,
    );
    expect(
      parseFocusedAnswer(raw('answered', [claim]), sources, c.book).note,
      isEmpty,
    );
    expect(
      () => parseFocusedAnswer(
        raw('answered', [claim, claim, claim]),
        sources,
        c.book,
      ),
      throwsFormatException,
    );
    expect(
      () => parseFocusedAnswer(
        raw('answered', [
          {
            'text': 'Wrong',
            'source_ids': ['S99'],
          },
        ]),
        sources,
        c.book,
      ),
      throwsFormatException,
    );
    expect(
      () => parseFocusedAnswer(raw('answered', [claim]), sources, 'other'),
      throwsFormatException,
    );
  });
}
