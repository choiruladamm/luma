import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/reading.dart';

void main() {
  test('readingMinutes rounds up, at least 1', () {
    expect(readingMinutes(0), 1);
    expect(readingMinutes(999), 1);
    expect(readingMinutes(1001), 2);
    expect(readingMinutes(6000), 6);
  });

  test('bookProgress: chapter offset plus how far into the chapter', () {
    double p(double f) => bookProgress(
      charOffset: 200,
      chapterChars: 100,
      fraction: f,
      totalChars: 1000,
    );
    expect(p(0), 0.2);
    expect(p(0.5), 0.25);
    expect(p(1), 0.3);
    expect(p(2), 0.3); // clamped
    expect(
      bookProgress(charOffset: 0, chapterChars: 0, fraction: 1, totalChars: 0),
      0,
    );
  });

  test('readingDays counts calendar days, same day = 1', () {
    expect(readingDays(DateTime(2026, 10, 7, 9), DateTime(2026, 10, 7, 23)), 1);
    expect(readingDays(DateTime(2026, 10, 1, 23), DateTime(2026, 10, 2, 1)), 2);
    // Across a DST switch and a month end.
    expect(readingDays(DateTime(2026, 3, 20), DateTime(2026, 4, 1)), 13);
    // Clock went backwards: still 1.
    expect(readingDays(DateTime(2026, 10, 8), DateTime(2026, 10, 7)), 1);
  });
}
