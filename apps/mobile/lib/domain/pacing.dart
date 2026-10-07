import 'dart:math' as math;

/// Ritme teks streaming (docs bagian 9): huruf dari jaringan ditampung,
/// dikeluarin rata, bukan per potongan. Aturan adaptif dari spike #34:
/// model ngalir 90–1000 huruf/detik (median 220–430), jadi batas 2× baseline
/// dari board bikin ketinggalan sampe 5 detik. Di sini kecepatan ngikutin
/// buffer, ketinggalan maks ±1 detik.
class Pacer {
  /// Huruf/detik minimal.
  static const baseline = 45.0;

  /// Kecepatan = buffer / ini, jadi ketinggalan gak lebih dari segini.
  static const lag = 1.0;

  /// Server selesai: sisa buffer abis dalam segini.
  static const drain = 0.6;

  /// Jawaban yang lengkap dalam segini sejak huruf pertama tampil langsung.
  static const instant = 1.5;

  double _shown = 0;
  double _elapsed = 0;
  double? _drainRate;

  /// Huruf yang boleh ditampilin.
  int get shown => _shown.floor();

  /// Maju [dt] detik. [available] = huruf yang udah dateng, [done] = server
  /// udah selesai. Balikin [shown].
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

  /// Tampilin semua sekarang (kepotong, kurangi gerakan).
  void finish(int available) => _shown = available.toDouble();
}
