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

/// Hari kalender dari [from] sampe [to], inklusif: hari yang sama = 1.
int readingDays(DateTime from, DateTime to) => math.max(
  1,
  DateTime.utc(
        to.year,
        to.month,
        to.day,
      ).difference(DateTime.utc(from.year, from.month, from.day)).inDays +
      1,
);
