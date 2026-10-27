import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_recovery.dart';
import '../support/book_chat_spike.dart';

void main() {
  final c = readCases().first;
  Passage source(String id, {String? book, String? hash}) => (
    id: id,
    book: book ?? c.book,
    revision: 1,
    chapter: '1',
    from: 0,
    to: 0,
    text: id,
    hash: hash ?? textHash(id),
  );
  test(
    'rewrite is bounded data without labels and rejects malformed output',
    () {
      final user = jsonDecode(searchRewriteUser(c)) as Map;
      expect(user.keys.toSet(), {'question', 'history'});
      expect(
        parseSearchRewrite(
          '{"query":"  What happened?  ","needs_clarification":false}',
        ).query,
        'What happened?',
      );
      expect(
        parseSearchRewrite(
          '{"query":"Why did they take it?","needs_clarification":true}',
        ).needsClarification,
        isTrue,
      );
      for (final bad in [
        '{}',
        '{"query":42}',
        '{"query":"x"}',
        '{"query":"x","needs_clarification":"true"}',
        '{"query":" ","needs_clarification":false}',
        jsonEncode({'query': 'x' * 2001, 'needs_clarification': false}),
      ]) {
        expect(() => parseSearchRewrite(bad), throwsFormatException);
      }
    },
  );
  test(
    'fusion retains scope, deduplicates votes, pins quote and caps candidates',
    () {
      final a = source('a');
      final b = source('b');
      final d = source('d');
      expect(
        recoveryCandidates(c, [
          [a, a, b],
          [b, a],
          [b, d],
        ]).map((p) => p.id),
        ['b', 'a', 'd'],
      );
      expect(
        recoveryCandidates(c, [
          [a, b],
          [a, b],
          [a, d],
        ], quoteId: 'd').first,
        d,
      );
      final many = List.generate(70, (i) => source('$i'));
      expect(recoveryCandidates(c, [many, many, many]).length, 40);
      expect(
        parseSearchRewrite(
          '{"query":"Why did they take it?","needs_clarification":true}',
        ).needsClarification,
        isTrue,
      );
      for (final bad in [
        source('x', book: 'foreign'),
        source('x', hash: 'stale'),
      ]) {
        expect(
          () => recoveryCandidates(c, [
            [a],
            [bad],
            [],
          ]),
          throwsFormatException,
        );
      }
      expect(
        () => recoveryCandidates(c, [
          [a],
          [],
          [],
        ], quoteId: 'missing'),
        throwsFormatException,
      );
    },
  );
}
