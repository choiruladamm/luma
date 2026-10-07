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

  test('charPosition: chapter offset plus the fraction of the chapter', () {
    int c(double f) =>
        charPosition(charOffset: 200, chapterChars: 100, fraction: f);
    expect(c(0), 200);
    expect(c(0.5), 250);
    expect(c(1), 300);
    expect(c(2), 300); // clamped
    expect(c(-1), 200);
  });

  test('formatReadingTime: hours and minutes, minutes only under an hour', () {
    expect(formatReadingTime(0), '0 mnt');
    expect(formatReadingTime(45 * 60 + 59), '45 mnt');
    expect(formatReadingTime(60 * 60), '1 jam 0 mnt');
    expect(formatReadingTime(6 * 3600 + 20 * 60 + 5), '6 jam 20 mnt');
  });

  group('ReadingClock', () {
    final t0 = DateTime(2026, 10, 7, 9);
    DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

    test('counts while interacting', () {
      final clock = ReadingClock(t0);
      clock.interact(at(30));
      clock.interact(at(90));
      expect(clock.take(at(100)), 100);
      expect(clock.take(at(100)), 0); // already taken
    });

    test('stops 2 minutes after the last interaction, resumes on the next', () {
      final clock = ReadingClock(t0);
      clock.interact(at(10));
      // Idle from 10s: counts until 130s, then nothing until 600s.
      expect(clock.take(at(500)), 130);
      clock.interact(at(600));
      expect(clock.take(at(660)), 60);
    });

    test('nothing counts in the background; resuming restarts the clock', () {
      final clock = ReadingClock(t0);
      clock.pause(at(50));
      clock.interact(at(100)); // can't happen in the background, ignored
      expect(clock.take(at(1000)), 50);
      clock.resume(at(2000));
      expect(clock.take(at(2030)), 30);
    });

    test('keeps fractions of a second for the next take', () {
      final clock = ReadingClock(t0);
      final half = t0.add(const Duration(milliseconds: 1500));
      expect(clock.take(half), 1);
      expect(clock.take(half.add(const Duration(milliseconds: 600))), 1);
    });
  });
}
