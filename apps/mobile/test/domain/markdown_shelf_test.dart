import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/models/markdown_shelf.dart';

void main() {
  const read = SlotState.read,
      reading = SlotState.reading,
      unread = SlotState.unread,
      missing = SlotState.missing;

  group('slots', () {
    test('one slot per number up to the highest, gaps are missing', () {
      const m = MarkdownShelf(chapters: [1, 3, 7], current: 3, fraction: 0.4);
      expect(m.count, 3); // chapters in, not the highest number
      expect(m.slots, [
        read,
        missing,
        reading,
        missing,
        missing,
        missing,
        unread,
      ]);
    });

    test('never opened: every present chapter is unread', () {
      const m = MarkdownShelf(chapters: [1, 2]);
      expect(m.slots, [unread, unread]);
      expect(m.barFraction, 0);
    });

    test('collapses past 16 numbers, not at 16', () {
      expect(
        MarkdownShelf(chapters: List.generate(16, (i) => i + 1)).collapsed,
        isFalse,
      );
      expect(
        MarkdownShelf(chapters: List.generate(17, (i) => i + 1)).collapsed,
        isTrue,
      );
      // Few chapters but a high number still collapses.
      expect(const MarkdownShelf(chapters: [120]).collapsed, isTrue);
    });
  });

  group('barFraction (fallback bar)', () {
    test('40 chapters, on 13 at 50%: 12.5 / 40', () {
      final m = MarkdownShelf(
        chapters: List.generate(40, (i) => i + 1),
        current: 13,
        fraction: 0.5,
      );
      expect(m.barFraction, closeTo(12.5 / 40, 1e-9));
    });

    test('only chapter 120, never opened: 0', () {
      expect(const MarkdownShelf(chapters: [120]).barFraction, 0);
    });

    test('only chapter 120, half read: 0.5', () {
      const m = MarkdownShelf(chapters: [120], current: 120, fraction: 0.5);
      expect(m.barFraction, 0.5);
    });
  });

  test('chapterRanges: runs of 3+ collapse, shorter stay listed', () {
    expect(chapterRanges([1, 3, 7]), 'Bab 1, 3, 7');
    expect(chapterRanges([1, 2]), 'Bab 1, 2');
    expect(chapterRanges(List.generate(40, (i) => i + 1)), 'Bab 1–40');
    expect(chapterRanges([1, 2, 3, 5, 9, 10, 11]), 'Bab 1–3, 5, 9–11');
    expect(chapterRanges([5], prefix: 'bab'), 'bab 5');
    expect(chapterRanges([]), 'Belum ada bab');
  });

  test('semanticLabel', () {
    const m = MarkdownShelf(chapters: [1, 3, 7], current: 3, fraction: 0.4);
    expect(
      m.semanticLabel('Atomic Habits'),
      'Atomic Habits, 3 bab, bab 1 udah dibaca, lagi baca bab 3',
    );
    expect(
      const MarkdownShelf(chapters: [1, 2]).semanticLabel('Deep Work'),
      'Deep Work, 2 bab',
    );
  });
}
