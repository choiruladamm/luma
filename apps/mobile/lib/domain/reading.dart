import 'dart:math' as math;

/// Kecepatan baca buat estimasi "±N mnt lagi". Sedikit di bawah rata-rata
/// pembaca native (±1.300 karakter/menit) soalnya bukunya dibaca sebagai
/// bahasa kedua. Tuning pas dogfooding.
const charsPerMinute = 1000;

/// Menit buat baca [chars] karakter, minimal 1.
int readingMinutes(int chars) => math.max(1, (chars / charsPerMinute).ceil());

/// Posisi baca di buku 0..1 dari posisi di chapter ([fraction] 0..1).
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

/// Durasi buat layar akhir buku: "6 jam 20 mnt", atau "45 mnt" di bawah 1 jam.
String formatReadingTime(int seconds) {
  final minutes = seconds ~/ 60;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h == 0 ? '$m mnt' : '$h jam $m mnt';
}

/// Ngitung waktu baca aktif: jalan selama halaman baca kebuka & app di depan,
/// berhenti kalau [idle] gak ada scroll/tap, lanjut lagi pas ada interaksi.
/// Waktu nunggu sampe idle ikut dihitung (lagi baca halaman yang sama).
class ReadingClock {
  ReadingClock(DateTime now) : _last = now, _until = now;

  static const idle = Duration(minutes: 2);

  /// Interaksi terakhir.
  DateTime _last;

  /// Udah dihitung sampe sini.
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

  /// App ke background.
  void pause(DateTime now) {
    _settle(now);
    _paused = true;
  }

  /// App balik ke depan: dianggap interaksi.
  void resume(DateTime now) {
    _paused = false;
    _last = _until = now;
  }

  /// Detik utuh yang belum disimpen; sisanya kebawa ke [take] berikutnya.
  int take(DateTime now) {
    _settle(now);
    final s = _pending.inSeconds;
    _pending -= Duration(seconds: s);
    return s;
  }
}
