import 'dart:math' as math;

/// Rhythm of streamed text (docs/llm.md): characters from the network are
/// buffered and released evenly, not per chunk. Adaptive rule from spike #34:
/// models stream 90–1000 chars/s (median 220–430), so the board's 2× baseline cap
/// lagged up to 5 seconds. Here the speed follows the buffer, lagging at most ±1 second.
class Pacer {
  /// Minimum characters per second.
  static const baseline = 45.0;

  /// Speed = buffer / this, so the lag never exceeds this many seconds.
  static const lag = 1.0;

  /// Server finished: the remaining buffer drains within this many seconds.
  static const drain = 0.6;

  /// An answer that is complete within this many seconds of the first shown character appears immediately.
  static const instant = 1.5;

  double _shown = 0;
  double _elapsed = 0;
  double? _drainRate;

  /// Characters allowed to be shown.
  int get shown => _shown.floor();

  /// Advances [dt] seconds. [available] = characters that have arrived, [done] = the
  /// server has finished. Returns [shown].
  int step(double dt, int available, {required bool done}) {
    _shown = math.min(_shown, available.toDouble());
    if (available <= 0) return shown;
    if (done && _drainRate == null) {
      if (_elapsed <= instant) {
        _drainRate = double.infinity;
      } else {
        _drainRate = (available - _shown) / drain;
      }
    }
    _elapsed += dt;
    final buffer = available - _shown;
    final rate = math.max(math.max(baseline, buffer / lag), _drainRate ?? 0);
    _shown = math.min(available.toDouble(), _shown + rate * dt);
    return shown;
  }

  /// Show everything now (truncated, reduce motion).
  void finish(int available) => _shown = available.toDouble();
}
