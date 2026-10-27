import 'package:flutter_test/flutter_test.dart';

import '../support/book_chat_recovery.dart';
import '../support/book_chat_refinement.dart';
import '../support/book_chat_spike.dart';

void main() {
  test(
    'multi-million-word book still sends bounded candidates and sources',
    () {
      final EvalCase c = (
        id: 'large',
        book: 'synthetic-large',
        question: 'marker10999 amber',
        expected: <List<String>>[],
        reason: '',
        history: <Map<String, dynamic>>[],
        quote: null,
      );
      // Synthetic corpus tests size/budget behavior, not semantic quality or device speed.
      final paragraphs = [
        for (var i = 0; i < 11000; i++)
          'marker$i ${List.filled(200, 'amber').join(' ')}',
      ];
      expect(
        paragraphs.fold<int>(0, (n, p) => n + words(p).length),
        greaterThan(2200000),
      );
      final corpus = [
        for (final (i, text) in paragraphs.indexed)
          (
            id: 'p$i',
            book: c.book,
            revision: 1,
            chapter: 'chapter${i ~/ 100}',
            from: i,
            to: i,
            text: text,
            hash: textHash(text),
          ),
      ];
      final ranked = LexicalIndex(corpus, c.book, 1).search(c.question, k: 40);
      expect(ranked.first.id, 'p10999');
      final candidates = recoveryCandidates(c, [ranked, ranked, ranked]);
      expect(candidates.length, 40);
      final selector = rerankUser(c, candidates);
      expect(
        bytes(selector) + bytes(recoverySelectionSystem),
        lessThanOrEqualTo(90000),
      );
      final selected = parseSelection(
        '{"selected":[1,2,3,4,5,6,7,8]}',
        candidates,
      );
      expect(selected.length, 8);
      expect(selected.first.id, 'p10999');
      final prompt = focusedUser(c, selected, {
        'title': 'Synthetic large book',
        'author': '',
      });
      expect(
        bytes(prompt) + bytes(recoveryAnswerSystem),
        lessThanOrEqualTo(promptBudget),
      );
      expect(prompt.contains('marker10999'), isTrue);
      expect(prompt.contains('marker9000 '), isFalse);
    },
  );
}
