/// Akhir kalimat: `.` `!` `?` `…` (boleh beruntun), tanda kutip / kurung
/// tutup ikut kalimat itu, terus spasi dan awal kalimat baru (huruf besar
/// atau tanda kutip / kurung buka).
final _end = RegExp(
  r'''[.!?…]+["”’'\)\]]*(?=\s+[\p{Lu}"“‘'(\[])''',
  unicode: true,
);

/// Kata sebelum titik yang bukan akhir kalimat (huruf kecil semua).
const _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'st', 'prof', 'jr', 'sr', 'vs', 'no', //
  'dll', 'dsb', 'dst', 'mis', 'dkk', 'sdr', 'tn', 'ny', 'yth',
};

/// Penomoran di awal teks (`IX.`, `3.`).
final _numbering = RegExp(r'^\s*([IVXLCDM]+|\d+)$');

/// Pecah [text] (satu paragraf terjemahan) jadi kalimat, buat penomoran
/// `K1..Kn` Bedahin. Gak pecah di singkatan, inisial (`J.`), angka desimal,
/// dan penomoran di awal. Hasilnya jadi kunci cache (rentang kalimat):
/// aturan berubah = naikin `breakdownPromptVersion`.
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
