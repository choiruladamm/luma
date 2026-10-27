import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_gold.dart';
import '../support/book_chat_heldout.dart';
import '../support/book_chat_retrieval.dart';

void main() {
  test('frozen pipeline inputs and prompt exclude evaluation labels', () {
    expect(verifyHeldoutProtocol(), hasLength(64));
    final inputs = heldoutInputs();
    expect(inputs, hasLength(40));
    final paragraphs = loadParagraphs(heldOut: true);
    final chunks = heldoutChunks(paragraphs);
    expect(chunks.map((s) => s.passage.book).toSet(), {
      'alice-in-wonderland',
      'meditations',
    });
    for (final c in inputs) {
      expect(c.input.expected, isEmpty);
      expect(c.input.reason, isEmpty);
      final owned = chunks
          .where((s) => s.passage.book == c.input.book)
          .toList();
      final quote = selectedWindow(c.input, owned);
      final ranked = [
        if (quote != null)
          owned.firstWhere((s) => s.passage.id == quote).passage,
        ...owned
            .where((s) => s.passage.id != quote)
            .take(7)
            .map((s) => s.passage),
      ];
      final user = jsonDecode(heldoutUser(c, ranked, paragraphs)) as Map;
      expect(
        user.keys.toSet().difference({
          'book',
          'question',
          'history',
          'selectedSourceId',
          'selectedQuote',
          'sources',
        }),
        isEmpty,
      );
      expect(user.containsKey('facts'), isFalse);
      expect(user.containsKey('expectedStatus'), isFalse);
      final query = heldoutQuery(c.input, chunks);
      expect(query, startsWith(heldoutQueryPrefix));
      expect(query, contains(c.input.question));
      if (c.selection != null) {
        expect(user['selectedQuote'], c.selection!.quote);
        expect(user['selectedSourceId'], 'S1');
      }
    }
  });
}
