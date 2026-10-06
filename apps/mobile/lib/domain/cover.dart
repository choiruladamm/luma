import 'dart:convert';

/// Indeks warna cover default 0..7 dari judul (board "Cover default · aturan
/// generate"). Judul sama = warna sama, di HP mana pun.
int coverIndex(String title) {
  final s = title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  var h = 0x811c9dc5; // FNV-1a 32-bit
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return ((h * 0x9e3779b1) & 0xffffffff) >> 29;
}

/// Huruf buat cover mini (< 64): huruf depan judul, lewatin "The", "A", "An".
String coverInitial(String title) {
  final words = title.trim().split(RegExp(r'\s+'));
  final skip = {'the', 'a', 'an'};
  final word = words.length > 1 && skip.contains(words.first.toLowerCase())
      ? words[1]
      : words.first;
  return word.isEmpty ? '?' : word.substring(0, 1).toUpperCase();
}

/// Lebar teks [text] (kapital) di ukuran [fontSize] dan sumbu lebar huruf
/// [width] (100 = normal, 75 = dipersempit).
typedef MeasureText = double Function(
  String text,
  double fontSize,
  double width,
);

class CoverTitleLine {
  const CoverTitleLine(this.text, this.fontSize);

  final String text;

  /// Biasanya ukuran step; lebih kecil kalau satu kata tetep gak muat.
  final double fontSize;
}

class CoverTitle {
  const CoverTitle({
    required this.lines,
    required this.fontSize,
    required this.width,
    required this.subtitle,
  });

  final List<CoverTitleLine> lines;
  final double fontSize;

  /// Sumbu `wdth`: 100 atau 75.
  final double width;

  /// Teks setelah ":" / ";" pertama, null kalau gak ada.
  final String? subtitle;
}

/// Padding cover = 0.085 × lebar di tiap sisi.
const coverPaddingFactor = 0.085;

// (ukuran × lebar cover, sumbu wdth, maks baris), dicoba berurutan.
const _steps = [
  (0.160, 100.0, 3),
  (0.140, 100.0, 4),
  (0.140, 75.0, 4),
  (0.120, 75.0, 5),
  (0.105, 75.0, 5),
  (0.092, 75.0, 6),
];

/// Tata letak judul cover default: kapital, pindah baris cuma di spasi, gak
/// pernah motong kata. Step pertama yang semua katanya muat & barisnya cukup
/// dipake. Mentok di step terakhir: kata yang tetep kepanjangan dikecilin di
/// barisnya aja, baris kebanyakan dipotong di batas kata + "…".
CoverTitle layoutCoverTitle(
  String title,
  double coverWidth,
  MeasureText measure,
) {
  final cut = title.indexOf(RegExp('[:;]'));
  final main = (cut == -1 ? title : title.substring(0, cut)).trim();
  final sub = cut == -1 ? '' : title.substring(cut + 1).trim();
  final words = main.toUpperCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  final inner = coverWidth * (1 - 2 * coverPaddingFactor);

  for (final (i, (factor, width, maxLines)) in _steps.indexed) {
    final size = factor * coverWidth;
    double w(String s) => measure(s, size, width);
    final lastStep = i == _steps.length - 1;
    if (!lastStep && words.any((word) => w(word) > inner)) continue;

    final lines = <String>[];
    for (final word in words) {
      if (lines.isNotEmpty && w('${lines.last} $word') <= inner) {
        lines.last = '${lines.last} $word';
      } else {
        lines.add(word);
      }
    }
    if (!lastStep && lines.length > maxLines) continue;

    if (lines.length > maxLines) {
      lines.removeRange(maxLines, lines.length);
      final kept = lines.last.split(' ');
      while (kept.length > 1 && w('${kept.join(' ')}…') > inner) {
        kept.removeLast();
      }
      lines.last = '${kept.join(' ')}…';
    }
    return CoverTitle(
      lines: [
        for (final line in lines)
          CoverTitleLine(line, w(line) > inner ? size * inner / w(line) : size),
      ],
      fontSize: size,
      width: width,
      subtitle: sub.isEmpty ? null : sub,
    );
  }
  throw StateError('unreachable: the last step always returns');
}
