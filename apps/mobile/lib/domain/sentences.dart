/// Sentence end: `.` `!` `?` `…` (may repeat), a closing quote / bracket belongs to
/// that sentence, then whitespace and the start of a new sentence (a capital letter
/// or an opening quote / bracket).
final _end = RegExp(
  r'''[.!?…]+["”’'\)\]]*(?=\s+[\p{Lu}"“‘'(\[])''',
  unicode: true,
);

/// Words before a period that don't end a sentence (all lowercase).
const _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'st', 'prof', 'jr', 'sr', 'vs', 'no', //
  'dll', 'dsb', 'dst', 'mis', 'dkk', 'sdr', 'tn', 'ny', 'yth',
};

/// Numbering at the start of the text (`IX.`, `3.`).
final _numbering = RegExp(r'^\s*([IVXLCDM]+|\d+)$');

/// Splits [text] (one translated paragraph) into sentences, for Bedahin's `K1..Kn`
/// numbering. Doesn't split at abbreviations, initials (`J.`), decimal numbers, or
/// leading numbering. The result keys the cache (sentence ranges): changing the
/// rules means bumping `breakdownPromptVersion`.
List<String> splitSentences(String text) {
  final out = <String>[];
  var start = 0;
  for (final m in _end.allMatches(text)) {
    final before = text.substring(start, m.start);
    if (m[0] == '.' && _keepsDot(before, isFirst: out.isEmpty)) continue;
    out.add(text.substring(start, m.end).trim());
    start = m.end;
  }
  final rest = text.substring(start).trim();
  if (rest.isNotEmpty) out.add(rest);
  return out;
}

bool _keepsDot(String before, {required bool isFirst}) {
  if (isFirst && _numbering.hasMatch(before)) return true;
  final word = RegExp(r'[\p{L}]+$', unicode: true).stringMatch(before);
  if (word == null) return false;
  if (word.length == 1 && word == word.toUpperCase()) return true;
  return _abbreviations.contains(word.toLowerCase());
}
