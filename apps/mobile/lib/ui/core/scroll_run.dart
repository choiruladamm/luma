/// Hasil [ScrollRun.add]: scroll udah cukup jauh buat ngumpetin / munculin
/// chrome (kapsul baca, header + tombol sheet).
enum ChromeIntent { hide, show }

/// Ambang ngumpet/munculin chrome ngikutin scroll: turun ≥ [hideAfter] →
/// [ChromeIntent.hide], naik ≥ [showAfter] → [ChromeIntent.show]. Ngitung
/// scroll searah yang belum nyampe ambang; ganti arah mulai dari nol.
class ScrollRun {
  static const hideAfter = 24.0;
  static const showAfter = 12.0;

  double _run = 0;

  /// [delta] > 0 = scroll turun (isi naik). Null kalau belum nyampe ambang.
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
