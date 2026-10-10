/// Satu slot di strip bab kartu buku Markdown (board Import Markdown 49).
enum SlotState {
  /// Udah dibaca sampai habis.
  read,

  /// Bab yang lagi dibaca, diisi sesuai fraksinya.
  reading,

  /// Udah masuk tapi belum dibuka.
  unread,

  /// Nomor ini belum di-import (di bawah nomor tertinggi yang udah masuk).
  missing,
}

/// Bab buku Markdown di rak: nomor yang udah masuk + posisi baca. Bab di
/// bawah posisi baca dianggap udah dibaca (posisi baca cuma satu per buku).
class MarkdownShelf {
  const MarkdownShelf({
    required this.chapters,
    this.current,
    this.fraction = 0,
  });

  /// Batas slot di strip; lebih dari ini strip jadi satu bar.
  static const maxSlots = 16;

  /// Nomor bab yang udah masuk, urut naik.
  final List<int> chapters;

  /// Nomor bab posisi baca; null = belum pernah dibuka.
  final int? current;

  /// 0..1 di dalam bab [current].
  final double fraction;

  /// Jumlah bab yang udah masuk (bukan nomor tertinggi).
  int get count => chapters.length;

  int get highest => chapters.isEmpty ? 0 : chapters.last;

  /// Nomor tertinggi > [maxSlots]: slot gak kebaca, strip jadi satu bar.
  bool get collapsed => highest > maxSlots;

  bool _isRead(int n) => current != null && n < current!;

  /// Satu slot per nomor bab, dari 1 sampai [highest].
  List<SlotState> get slots {
    final have = chapters.toSet();
    return [
      for (var n = 1; n <= highest; n++)
        if (!have.contains(n))
          SlotState.missing
        else if (_isRead(n))
          SlotState.read
        else if (n == current)
          SlotState.reading
        else
          SlotState.unread,
    ];
  }

  /// Isi bar fallback: bab dibaca ÷ bab masuk, plus fraksi bab yang lagi
  /// dibaca.
  double get barFraction {
    if (chapters.isEmpty || current == null) return 0;
    final read = chapters.where(_isRead).length;
    final reading = chapters.contains(current) ? fraction : 0;
    return ((read + reading) / count).clamp(0, 1).toDouble();
  }

  /// "Bab 1, 3, 7" / "Bab 1–40".
  String get label => chapterRanges(chapters);

  /// "Atomic Habits, 3 bab, bab 1 udah dibaca, lagi baca bab 3".
  String semanticLabel(String title) {
    final parts = [title, '$count bab'];
    final read = chapters.where(_isRead).toList();
    if (read.isNotEmpty) {
      parts.add('${chapterRanges(read, prefix: 'bab')} udah dibaca');
    }
    if (chapters.contains(current)) parts.add('lagi baca bab $current');
    return parts.join(', ');
  }
}

/// Nomor bab jadi teks: 3 nomor berurutan atau lebih diringkas jadi rentang.
/// [1, 3, 7] → "Bab 1, 3, 7"; [1, 2] → "Bab 1, 2"; 1..40 → "Bab 1–40".
String chapterRanges(List<int> chapters, {String prefix = 'Bab'}) {
  if (chapters.isEmpty) return 'Belum ada bab';
  final parts = <String>[];
  var i = 0;
  while (i < chapters.length) {
    var j = i;
    while (j + 1 < chapters.length && chapters[j + 1] == chapters[j] + 1) {
      j++;
    }
    if (j - i >= 2) {
      parts.add('${chapters[i]}–${chapters[j]}');
    } else {
      for (var k = i; k <= j; k++) {
        parts.add('${chapters[k]}');
      }
    }
    i = j + 1;
  }
  return '$prefix ${parts.join(', ')}';
}
