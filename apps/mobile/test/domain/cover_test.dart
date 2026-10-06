import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/cover.dart';

/// Monospace stand-in: every glyph is 0.6em wide, narrowed by the wdth axis.
double fake(String text, double size, double width) =>
    text.length * size * 0.6 * width / 100;

void main() {
  test('coverIndex matches the board colours', () {
    // 0 kuning · 1 pink · 2 peach · 3 mint · 4 periwinkle · 5 lilac · 6 langit · 7 sage
    expect(coverIndex('Pride and Prejudice'), 1);
    expect(coverIndex('Frankenstein'), 5);
    expect(coverIndex('The Adventures of Sherlock Holmes'), 7);
    expect(coverIndex('The Picture of Dorian Gray'), 5);
    expect(coverIndex('Sapiens: A Brief History of Humankind'), 7);
  });

  test('coverIndex ignores case and extra spaces', () {
    expect(
      coverIndex('  pride  AND prejudice '),
      coverIndex('Pride and Prejudice'),
    );
    for (final t in ['', 'a', 'Meditations', 'Ἐγχειρίδιον']) {
      expect(coverIndex(t), inInclusiveRange(0, 7));
    }
  });

  test('coverInitial skips leading articles', () {
    expect(coverInitial('The Picture of Dorian Gray'), 'P');
    expect(coverInitial('a tale'), 'T');
    expect(coverInitial('An'), 'A');
    expect(coverInitial('Emma'), 'E');
  });

  group('layoutCoverTitle', () {
    const w = 100.0; // inner = 83

    test('short title: first step, one line', () {
      final t = layoutCoverTitle('Emma', w, fake);
      expect(t.fontSize, 16);
      expect(t.width, 100);
      expect(t.lines.map((l) => l.text), ['EMMA']);
    });

    test('a word too wide for a step moves on, never splitting it', () {
      // 12 letters: 0.6 × 14 × 12 = 100.8 > 83 at wdth 100, 75.6 at 75.
      final t = layoutCoverTitle('Frankenstein', w, fake);
      expect(t.fontSize, closeTo(14, 1e-9));
      expect(t.width, 75);
      expect(t.lines.single.text, 'FRANKENSTEIN');
    });

    test('lines wrap at spaces only and every word survives', () {
      const title = 'The Life and Opinions of Tristram Shandy, Gentleman';
      final t = layoutCoverTitle(title, w, fake);
      expect(t.lines.map((l) => l.text).join(' '), title.toUpperCase());
      for (final l in t.lines) {
        expect(fake(l.text, l.fontSize, t.width), lessThanOrEqualTo(83));
      }
    });

    test('subtitle splits off at the first colon or semicolon', () {
      final t = layoutCoverTitle('Sapiens: A Brief History; of Us', w, fake);
      expect(t.lines.map((l) => l.text), ['SAPIENS']);
      expect(t.subtitle, 'A Brief History; of Us');
    });

    test('last step: an overlong word shrinks on its own line', () {
      final t = layoutCoverTitle('Supercalifragilisticexpialidocious', w, fake);
      final line = t.lines.single;
      expect(t.fontSize, closeTo(9.2, 1e-9));
      expect(line.fontSize, lessThan(t.fontSize));
      expect(fake(line.text, line.fontSize, t.width), closeTo(83, 1e-6));
    });

    test('last step: too many lines are cut at a word with an ellipsis', () {
      final t = layoutCoverTitle(List.filled(40, 'word').join(' '), w, fake);
      expect(t.lines, hasLength(6));
      expect(t.lines.last.text, endsWith('WORD…'));
      expect(
        fake(t.lines.last.text, t.fontSize, t.width),
        lessThanOrEqualTo(83),
      );
    });
  });
}
