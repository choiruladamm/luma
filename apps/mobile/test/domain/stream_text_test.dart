import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/stream_text.dart';

void main() {
  group('splitTail', () {
    test('the last 4 words fade, the rest stays solid', () {
      final t = splitTail('Mr. Bennet menjawab belum, katanya pelan');
      expect(t.head, 'Mr. Bennet ');
      expect(t.tail, ['menjawab ', 'belum, ', 'katanya ', 'pelan']);
    });

    test('fewer words: all of them fade, nothing lost', () {
      expect(splitTail('Halo dunia').tail, ['Halo ', 'dunia']);
      expect(splitTail('Halo dunia').head, '');
      expect(splitTail('').tail, isEmpty);
      expect(splitTail('   ').head, '   ');
    });

    test('joins back to the same text', () {
      const s = '“Tapi memang sudah,” balas istrinya;  “Mrs. Long ';
      final t = splitTail(s);
      expect(t.head + t.tail.join(), s);
    });
  });

  group('placeholderRows', () {
    test('board example: Jelas 18.5, column 342, 3 lines for P1', () {
      // "My dear Mr. Bennet…" is 106 letters → × 1.05 ≈ 111 → 2.7 lines.
      final rows = placeholderRows(estimateTranslation(106), 0.455 * 18.5, 342);
      expect(rows, hasLength(3));
      expect(rows.first, 1.0);
      expect(rows.last, closeTo(0.74, 0.02));
    });

    test('a short line keeps a visible width; nothing for nothing', () {
      expect(placeholderRows(1, 8, 300), [0.25]);
      expect(placeholderRows(0, 8, 300), isEmpty);
    });

    test('estimates', () {
      expect(estimateTranslation(100), 105);
      expect(estimatedMeaning, 130);
    });
  });
}
