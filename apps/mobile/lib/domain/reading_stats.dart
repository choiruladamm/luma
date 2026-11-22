import 'dart:math' as math;

import 'reading.dart';

/// One saved `reading_sessions` row, as the statistics need it.
typedef ReadingSlice = ({
  DateTime startedAt,
  int seconds,
  int startChar,
  int endChar,
});

/// Fastest reading credited, in characters per second: three times the
/// [charsPerMinute] estimate. A slice that covers more than this was skimmed
/// or jumped (table of contents, search), so only this much counts.
// ponytail: a guessed ceiling until dogfooding data gives a measured one;
// tune it from real slices.
const maxCharsPerSecond = charsPerMinute * 3 / 60;

/// Characters actually read in [slice]: the forward distance, capped by its
/// active seconds at [maxCharsPerSecond]. Scrolling back counts as nothing.
int charsRead(ReadingSlice slice) {
  final moved = slice.endChar - slice.startChar;
  if (moved <= 0) return 0;
  return math.min(moved, (slice.seconds * maxCharsPerSecond).floor());
}

/// The local calendar day of [at], as local midnight.
DateTime localDay(DateTime at) {
  final t = at.toLocal();
  return DateTime(t.year, t.month, t.day);
}

/// Monday (local midnight) of the week that holds [at].
DateTime weekStart(DateTime at) {
  final day = localDay(at);
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}

/// Consecutive reading days ending today, or ending yesterday when today has
/// no reading yet: a day that isn't over doesn't break the streak.
int streak(Iterable<DateTime> readAt, DateTime now) {
  final days = {for (final t in readAt) localDay(t)};
  var day = localDay(now);
  if (!days.contains(day)) day = DateTime(day.year, day.month, day.day - 1);
  var count = 0;
  while (days.contains(day)) {
    count++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return count;
}

/// Total active seconds per local day, keyed by local midnight.
Map<DateTime, int> secondsPerDay(Iterable<ReadingSlice> slices) {
  final out = <DateTime, int>{};
  for (final s in slices) {
    final day = localDay(s.startedAt);
    out[day] = (out[day] ?? 0) + s.seconds;
  }
  return out;
}

/// Active seconds this week and last week (weeks start on Monday).
({int thisWeek, int lastWeek}) weekSeconds(
  Iterable<ReadingSlice> slices,
  DateTime now,
) {
  final start = weekStart(now);
  final lastStart = DateTime(start.year, start.month, start.day - 7);
  var thisWeek = 0, lastWeek = 0;
  for (final s in slices) {
    final at = s.startedAt.toLocal();
    if (!at.isBefore(start)) {
      thisWeek += s.seconds;
    } else if (!at.isBefore(lastStart)) {
      lastWeek += s.seconds;
    }
  }
  return (thisWeek: thisWeek, lastWeek: lastWeek);
}

/// Time left to read [remainingChars] at the speed of [recent] slices (their
/// [charsRead] over their active seconds). Zero when nothing is left; null
/// when the recent slices show no measurable speed yet.
Duration? estimatedFinish({
  required int remainingChars,
  required Iterable<ReadingSlice> recent,
}) {
  if (remainingChars <= 0) return Duration.zero;
  var chars = 0, seconds = 0;
  for (final s in recent) {
    chars += charsRead(s);
    seconds += s.seconds;
  }
  if (chars == 0 || seconds == 0) return null;
  return Duration(seconds: (remainingChars * seconds / chars).ceil());
}

/// Active seconds per local hour of the day where each slice started (index
/// 0..23).
List<int> secondsPerHour(Iterable<ReadingSlice> slices) {
  final out = List.filled(24, 0);
  for (final s in slices) {
    out[s.startedAt.toLocal().hour] += s.seconds;
  }
  return out;
}

/// Active seconds per local weekday where each slice started, Monday first
/// (index 0..6).
List<int> secondsPerWeekday(Iterable<ReadingSlice> slices) {
  final out = List.filled(7, 0);
  for (final s in slices) {
    out[s.startedAt.toLocal().weekday - 1] += s.seconds;
  }
  return out;
}

/// Index of the largest value, or null when every value is zero.
int? busiest(List<int> values) {
  var best = -1, at = -1;
  for (var i = 0; i < values.length; i++) {
    if (values[i] > best) (best, at) = (values[i], i);
  }
  return best > 0 ? at : null;
}

/// Reading speed over [slices] in characters per minute ([charsRead] over
/// active time), or null when they show no measurable reading.
double? charsPerMinuteOf(Iterable<ReadingSlice> slices) {
  var chars = 0, seconds = 0;
  for (final s in slices) {
    chars += charsRead(s);
    seconds += s.seconds;
  }
  if (chars == 0 || seconds == 0) return null;
  return chars * 60 / seconds;
}
