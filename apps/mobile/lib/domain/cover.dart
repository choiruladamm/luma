import 'dart:convert';

/// Default cover color index 0..7 from the title (board "Cover default · aturan
/// generate"). The same title gives the same color on any phone.
int coverIndex(String title) {
  final s = title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  var h = 0x811c9dc5; // FNV-1a 32-bit
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return ((h * 0x9e3779b1) & 0xffffffff) >> 29;
}

/// Letter for the mini cover (< 64): the title's first letter, skipping "The", "A", "An".
String coverInitial(String title) {
  final words = title.trim().split(RegExp(r'\s+'));
  final skip = {'the', 'a', 'an'};
  final word = words.length > 1 && skip.contains(words.first.toLowerCase())
      ? words[1]
      : words.first;
  return word.isEmpty ? '?' : word.substring(0, 1).toUpperCase();
}

/// Width of [text] (uppercase) at [fontSize] and width axis [width] (100 = normal,
/// 75 = condensed).
typedef MeasureText = double Function(
  String text,
  double fontSize,
  double width,
);

class CoverTitleLine {
  const CoverTitleLine(this.text, this.fontSize);

  final String text;

  /// Usually the step size; smaller when a single word still doesn't fit.
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

  /// The `wdth` axis: 100 or 75.
  final double width;

  /// Text after the first ":" / ";", null when absent.
  final String? subtitle;
}

/// Cover padding = 0.085 × width on each side.
const coverPaddingFactor = 0.085;

// (size × cover width, wdth axis, max lines), tried in order.
const _steps = [
  (0.160, 100.0, 3),
  (0.140, 100.0, 4),
  (0.140, 75.0, 4),
  (0.120, 75.0, 5),
  (0.105, 75.0, 5),
  (0.092, 75.0, 6),
];

/// Default cover title layout: uppercase, wraps only at spaces, never splits a
/// word. The first step where all words fit and the lines suffice is used. At the
/// last step: a word that is still too long is shrunk on its own line only, and
/// too many lines are cut at a word boundary + "…".
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
