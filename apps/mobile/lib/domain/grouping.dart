import 'models/book.dart';

/// Defines grouping rules (docs/grouping.md).
/// Changes require a `parserVersion` bump because existing group indices become invalid.
abstract final class GroupRules {
  /// Paragraphs at least this long form their own group.
  static const longThreshold = 300;

  /// Groups close after reaching this size.
  static const targetChars = 450;

  /// The maximum group size.
  static const maxChars = 800;
  static const maxParagraphs = 6;
}

/// Assigns zero-based group indices to consecutive short paragraphs.
/// Headings and scene breaks receive `null` and always break groups.
List<int?> assignGroups(List<RawParagraph> paras) {
  final result = List<int?>.filled(paras.length, null);
  final current = <int>[];
  var currentChars = 0;
  var groupIndex = 0;

  void flush() {
    if (current.isEmpty) return;
    for (final i in current) {
      result[i] = groupIndex;
    }
    groupIndex++;
    current.clear();
    currentChars = 0;
  }

  for (final (i, p) in paras.indexed) {
    if (p.type != ParagraphType.paragraph) {
      flush();
      continue;
    }

    final len = p.text.length;
    if (len >= GroupRules.longThreshold) {
      flush();
      current.add(i);
      flush();
      continue;
    }

    if (current.isNotEmpty &&
        (currentChars + len > GroupRules.maxChars ||
            current.length >= GroupRules.maxParagraphs)) {
      flush();
    }

    current.add(i);
    currentChars += len;
    if (currentChars >= GroupRules.targetChars) flush();
  }

  flush();
  return result;
}
