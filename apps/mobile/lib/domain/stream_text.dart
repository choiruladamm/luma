import 'dart:math' as math;

/// Opacity of the last 4 words of the text being written (board "Artinya streaming
/// · Opsi B"): more transparent toward the end, static.
const tailAlphas = [0.8, 0.6, 0.42, 0.26];

/// Splits [text] into a solid part + tail words (at most [tailAlphas] long). Each
/// tail word carries its trailing space, so joining them reproduces [text] exactly.
/// Tail words get alphas from the end: 2 words = 0.42 · 0.26.
({String head, List<String> tail}) splitTail(String text) {
  final words = RegExp(r'\S+').allMatches(text).toList();
  if (words.isEmpty) return (head: text, tail: const []);
  final from = math.max(0, words.length - tailAlphas.length);
  return (
    head: text.substring(0, words[from].start),
    tail: [
      for (var i = from; i < words.length; i++)
        text.substring(
          words[i].start,
          i + 1 < words.length ? words[i + 1].start : text.length,
        ),
    ],
  );
}

/// Approximate number of characters of the translation of an original paragraph of length [source].
double estimateTranslation(int source) => source * 1.05;

/// Approximate number of characters of the meaning block.
const estimatedMeaning = 130.0;

/// Width of a placeholder line (fraction of the column width) for text of [chars]
/// characters (behavior board): lines = ⌈chars × average char width ÷ column
/// width⌉, the last line as wide as the remainder.
List<double> placeholderRows(double chars, double charWidth, double column) {
  if (chars <= 0 || column <= 0) return const [];
  final lines = chars * charWidth / column;
  final count = lines.ceil();
  final last = (lines - (count - 1)).clamp(0.25, 1.0);
  return [for (var i = 0; i < count - 1; i++) 1.0, last];
}
