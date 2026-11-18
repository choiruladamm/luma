/// Result of [ScrollRun.add]: scrolled far enough to hide or reveal
/// the chrome (reading capsule, header + sheet buttons).
enum ChromeIntent { hide, show }

/// Thresholds for hiding/revealing chrome while scrolling: down ≥ [hideAfter] →
/// [ChromeIntent.hide], up ≥ [showAfter] → [ChromeIntent.show]. Tracks
/// same-direction scroll short of a threshold; a direction change restarts at zero.
class ScrollRun {
  static const hideAfter = 24.0;
  static const showAfter = 12.0;

  double _run = 0;

  /// [delta] > 0 = scrolling down (content moves up). Null until a threshold is reached.
  ChromeIntent? add(double delta) {
    if (delta == 0) return null;
    if ((delta > 0) != (_run > 0)) _run = 0;
    _run += delta;
    if (_run >= hideAfter) {
      _run = 0;
      return ChromeIntent.hide;
    }
    if (_run <= -showAfter) {
      _run = 0;
      return ChromeIntent.show;
    }
    return null;
  }

  void reset() => _run = 0;
}
