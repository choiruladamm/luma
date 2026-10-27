import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_gold.dart';
import '../support/book_chat_heldout.dart';
import '../support/book_chat_refinement.dart';
import '../support/book_chat_retrieval.dart';
import '../support/book_chat_validation2.dart';

void main() {
  test('fresh book validation labels resolve and never enter model inputs', () {
    expect(verifyValidation2(), hasLength(64));
    final corpus = validation2Corpus();
    final inputs = validation2Inputs();
    final gold = readGold(validation2File);
    expect(inputs, hasLength(40));
    expect(gold.where((g) => g.facts.isNotEmpty), hasLength(30));
    expect(
      corpus.paragraphs.map((p) => p.book).toSet(),
      validation2Books.toSet(),
    );
    expect(
      corpus.paragraphs
          .map((p) => p.book)
          .toSet()
          .intersection(
            loadParagraphs(heldOut: true).map((p) => p.book).toSet(),
          ),
      isEmpty,
    );
    for (final c in inputs) {
      final g = gold.firstWhere((g) => g.id == c.input.id);
      expect(c.input.expected, isEmpty);
      expect(c.input.reason, isEmpty);
      for (final f in g.facts) {
        for (final e in f.alternatives) {
          resolveEvidence(e, corpus.paragraphs, c.input.book);
        }
      }
      if (c.selection != null) {
        resolveEvidence(c.selection!, corpus.paragraphs, c.input.book);
      }
      final owned = corpus.chunks
          .where((s) => s.passage.book == c.input.book)
          .toList();
      final quote = selectedWindow(c.input, owned);
      final sources = [
        if (quote != null)
          owned.firstWhere((s) => s.passage.id == quote).passage,
        ...owned
            .where((s) => s.passage.id != quote)
            .take(7)
            .map((s) => s.passage),
      ];
      expect(heldoutQuery(c.input, owned), contains(c.input.question));
      final user = focusedUser(
        c.input,
        sources,
        corpus.metadata[c.input.book]!,
        quoteId: quote,
        quoteText: c.selection?.quote,
      );
      expect(user, contains(c.input.question));
      expect(user, isNot(contains('expectedStatus')));
    }
  });
}
