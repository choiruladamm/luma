import 'models/book.dart';

/// Aturan grouping (docs/grouping.md). Nilai awal, di-tuning pas dogfooding.
/// Ubah = naikin `parserVersion`: indeks grup lama jadi gak valid.
abstract final class GroupRules {
  /// Paragraf ≥ ini berdiri sendiri sebagai satu grup.
  static const longThreshold = 300;

  /// Grup ditutup setelah nyampe ukuran ini.
  static const targetChars = 450;

  /// Grup gak boleh lewat ini.
  static const maxChars = 800;
  static const maxParagraphs = 6;
}

/// `groupIndex` per paragraf di satu chapter, mulai dari 0. Paragraf pendek
/// yang berurutan digabung; heading & scene break dapet `null` dan selalu
/// mutus grup.
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
