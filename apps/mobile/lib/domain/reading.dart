import 'dart:math' as math;

/// Reading speed for the "±N mnt lagi" estimate. Slightly below the average native
/// reader (±1,300 characters/minute) because the book is read as a second language.
/// Tune while dogfooding.
const charsPerMinute = 1000;

/// Minutes to read [chars] characters, at least 1.
int readingMinutes(int chars) => math.max(1, (chars / charsPerMinute).ceil());

/// Absolute position in the book (characters) from the position in the chapter
/// ([fraction] 0..1). Source of `startChar` / `endChar` in `reading_sessions`.
int charPosition({
  required int charOffset,
  required int chapterChars,
  required double fraction,
}) => charOffset + (fraction.clamp(0, 1) * chapterChars).round();

/// Reading position in the book 0..1 from the position in the chapter ([fraction] 0..1).
double bookProgress({
  required int charOffset,
  required int chapterChars,
  required double fraction,
  required int totalChars,
}) => totalChars <= 0
    ? 0
    : ((charOffset + fraction.clamp(0, 1) * chapterChars) / totalChars)
          .clamp(0, 1)
          .toDouble();

/// Counts active reading time: runs while the reading page is open and the app is in
/// the foreground, stops when [idle] passes without scroll/tap, resumes on interaction.
/// The wait until idle is still counted (reading the same page).
class ReadingClock {
  ReadingClock(DateTime now) : _last = now, _until = now;

  static const idle = Duration(minutes: 2);

  /// Last interaction.
  DateTime _last;

  /// Counted up to here.
  DateTime _until;
  bool _paused = false;
  Duration _pending = Duration.zero;

  void _settle(DateTime now) {
    if (_paused) return;
    final cap = _last.add(idle);
    final end = now.isBefore(cap) ? now : cap;
    if (end.isAfter(_until)) {
      _pending += end.difference(_until);
      _until = end;
    }
  }

  /// Scroll / tap.
  void interact(DateTime now) {
    if (_paused) return;
    _settle(now);
    _last = _until = now;
  }

  /// The app went to the background.
  void pause(DateTime now) {
    _settle(now);
    _paused = true;
  }

  /// The app came back to the foreground: counts as an interaction.
  void resume(DateTime now) {
    _paused = false;
    _last = _until = now;
  }

  /// Whole seconds not yet saved; the remainder carries over to the next [take].
  int take(DateTime now) {
    _settle(now);
    final s = _pending.inSeconds;
    _pending -= Duration(seconds: s);
    return s;
  }
}
