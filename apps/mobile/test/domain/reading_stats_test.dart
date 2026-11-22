import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/reading_stats.dart';

ReadingSlice slice(
  DateTime at, {
  int seconds = 60,
  int start = 0,
  int end = 0,
}) => (startedAt: at, seconds: seconds, startChar: start, endChar: end);

void main() {
  group('charsRead', () {
    test('counts the forward distance', () {
      expect(charsRead(slice(DateTime(2026), end: 900)), 900);
    });

    test('caps a jump at the speed limit', () {
      // 60 s at 50 chars/s.
      expect(charsRead(slice(DateTime(2026), end: 100000)), 3000);
    });

    test('scrolling back or standing still counts nothing', () {
      expect(charsRead(slice(DateTime(2026), start: 500, end: 200)), 0);
      expect(charsRead(slice(DateTime(2026), start: 500, end: 500)), 0);
    });
  });

  group('streak', () {
    final now = DateTime(2026, 3, 2, 9);

    test('counts back from today across a month boundary', () {
      final days = [
        DateTime(2026, 3, 2, 7),
        DateTime(2026, 3, 1, 22),
        DateTime(2026, 2, 28, 12),
        DateTime(2026, 2, 28, 13),
        DateTime(2026, 2, 26), // gap on the 27th
      ];
      expect(streak(days, now), 3);
    });

    test('not having read yet today keeps yesterday\'s streak', () {
      expect(streak([DateTime(2026, 3), DateTime(2026, 2, 28)], now), 2);
    });

    test('a skipped day breaks it', () {
      expect(streak([DateTime(2026, 2, 28)], now), 0);
      expect(streak(const [], now), 0);
    });
  });

  group('weeks', () {
    test('a week starts on Monday', () {
      // 2026-11-22 is a Sunday; its week starts Monday the 16th.
      expect(weekStart(DateTime(2026, 11, 22, 23)), DateTime(2026, 11, 16));
      expect(weekStart(DateTime(2026, 11, 16)), DateTime(2026, 11, 16));
      expect(weekStart(DateTime(2026, 12, 2)), DateTime(2026, 11, 30));
    });

    test('this week vs last week', () {
      final now = DateTime(2026, 11, 18, 12); // Wednesday
      final slices = [
        slice(DateTime(2026, 11, 16), seconds: 100), // this Monday
        slice(DateTime(2026, 11, 18), seconds: 50),
        slice(DateTime(2026, 11, 15, 23), seconds: 30), // last Sunday
        slice(DateTime(2026, 11, 9), seconds: 20), // last Monday
        slice(DateTime(2026, 11, 8), seconds: 999), // two weeks ago
      ];
      expect(weekSeconds(slices, now), (thisWeek: 150, lastWeek: 50));
    });

    test('seconds per local day', () {
      final days = secondsPerDay([
        slice(DateTime(2026, 11, 18, 8), seconds: 10),
        slice(DateTime(2026, 11, 18, 21), seconds: 5),
        slice(DateTime(2026, 11, 17), seconds: 7),
      ]);
      expect(days, {DateTime(2026, 11, 18): 15, DateTime(2026, 11, 17): 7});
    });
  });

  group('estimatedFinish', () {
    final recent = [
      slice(DateTime(2026), end: 600),
      slice(DateTime(2026), start: 600, end: 1200),
    ];

    test('remaining characters at the recent speed', () {
      // 1,200 chars in 120 s = 10 chars/s.
      expect(
        estimatedFinish(remainingChars: 3000, recent: recent),
        const Duration(seconds: 300),
      );
    });

    test('nothing left is zero, no measurable speed is null', () {
      expect(estimatedFinish(remainingChars: 0, recent: recent), Duration.zero);
      expect(estimatedFinish(remainingChars: 10, recent: const []), isNull);
      expect(
        estimatedFinish(
          remainingChars: 10,
          recent: [slice(DateTime(2026), start: 50, end: 10)],
        ),
        isNull,
      );
    });
  });
}
