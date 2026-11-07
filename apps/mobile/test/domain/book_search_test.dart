import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/book_search.dart';

void main() {
  group('BookSearchQuery.parse', () {
    test('needs at least 2 letters or digits', () {
      expect(BookSearchQuery.parse(''), isNull);
      expect(BookSearchQuery.parse('  a '), isNull);
      expect(BookSearchQuery.parse('--*'), isNull);
      expect(BookSearchQuery.parse('ab'), isNotNull);
      expect(BookSearchQuery.parse('1 2'), isNotNull);
    });

    test('words become one phrase, last word is a prefix', () {
      expect(BookSearchQuery.parse('netherfield')!.match, '"netherfield"*');
      expect(
        BookSearchQuery.parse('  Netherfield   PARK ')!.match,
        '"netherfield park"*',
      );
    });

    test('FTS syntax and quotes from the user never reach MATCH', () {
      for (final evil in ['"a" OR b', 'x* NEAR y', '-foo', 'a"b"c', 'ab" *']) {
        final m = BookSearchQuery.parse(evil)!.match;
        expect(
          RegExp(r'^"[\p{L}\p{N} ]+"\*$', unicode: true).hasMatch(m),
          true,
        );
      }
      expect(BookSearchQuery.parse('"a" OR b')!.match, '"a or b"*');
    });

    test('accents, case and curly quotes fold to the same query', () {
      expect(
        BookSearchQuery.parse('CAFÉ')!.match,
        BookSearchQuery.parse('cafe')!.match,
      );
      expect(
        BookSearchQuery.parse('don’t')!.match,
        BookSearchQuery.parse("don't")!.match,
      );
    });
  });

  group('ranges', () {
    test('finds whole words and extends the prefix word', () {
      final q = BookSearchQuery.parse('nether')!;
      const text = 'Mrs. Long says Netherfield is taken.';
      expect(q.ranges(text), [(start: 15, end: 26)]);
      expect(text.substring(15, 26), 'Netherfield');
    });

    test('phrase must be adjacent, case and accent blind', () {
      final q = BookSearchQuery.parse('cafe near')!;
      expect(q.ranges('A Café near Brontë.'), [(start: 2, end: 11)]);
      expect(q.ranges('A cafe, far near'), isEmpty);
    });

    test('curly and straight apostrophes match each other', () {
      final q = BookSearchQuery.parse("don't")!;
      expect(q.ranges('I don’t know'), [(start: 2, end: 7)]);
    });

    test('every occurrence, no overlap, indices fit the original text', () {
      final q = BookSearchQuery.parse('aa aa')!;
      const text = 'Aa aa aa aa';
      expect(q.ranges(text), [(start: 0, end: 5), (start: 6, end: 11)]);
    });

    test('mid-word match does not count', () {
      expect(BookSearchQuery.parse('ether')!.ranges('Netherfield'), isEmpty);
    });
  });

  group('bookSearchSnippet', () {
    test('short text stays whole, offsets point at the match', () {
      const text = 'Netherfield is let.';
      final s = bookSearchSnippet(text, (start: 0, end: 11));
      expect(s.text, text);
      expect(s.text.substring(s.matchStart, s.matchEnd), 'Netherfield');
    });

    test('cuts ±60 chars with ellipsis on both sides', () {
      final text = '${'x ' * 100}NEEDLE${' y' * 100}';
      final start = text.indexOf('NEEDLE');
      final s = bookSearchSnippet(text, (start: start, end: start + 6));
      expect(s.text, startsWith('…'));
      expect(s.text, endsWith('…'));
      expect(s.text.substring(s.matchStart, s.matchEnd), 'NEEDLE');
      expect(s.text.length, lessThanOrEqualTo(6 + 2 * 60 + 2));
    });

    test('match near the start has no leading ellipsis', () {
      final text = 'NEEDLE${' y' * 100}';
      final s = bookSearchSnippet(text, (start: 0, end: 6));
      expect(s.text, startsWith('NEEDLE'));
      expect(s.text, endsWith('…'));
      expect(s.matchStart, 0);
    });

    test('no match in text falls back to the paragraph start', () {
      final s = bookSearchSnippet('word ' * 100, null);
      expect(s.text, startsWith('word word'));
      expect(s.text, endsWith('…'));
      expect((s.matchStart, s.matchEnd), (0, 0));
    });
  });
}
