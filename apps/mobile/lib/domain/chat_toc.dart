/// Daftar isi asli buku untuk perencanaan Ngobrol (#143): identitas bab dari
/// `chapters.id`, label TOC asli, section induk ("Discourses › Book I"), dan
/// ukuran. Model memilih bab lewat `id`; aplikasi memvalidasi, bukan percaya.
typedef ChatChapterInfo = ({int id, String title, String? section, int chars});

const _roman = {
  'M': 1000,
  'D': 500,
  'C': 100,
  'L': 50,
  'X': 10,
  'V': 5,
  'I': 1,
};

/// Angka Romawi/Arab di awal label ("III: Of…", "XXIX.", "Chapter 7") → 7.
/// Null kalau tidak ada nomor di depan.
int? chatChapterNumber(String title) {
  final m = RegExp(
    r'^(?:(?:chapter|bab|book|buku|part|bagian)\s+)?([IVXLCDM]+|\d+)\b',
    caseSensitive: false,
  ).firstMatch(title.trim());
  if (m == null) return null;
  final token = m.group(1)!;
  final arabic = int.tryParse(token);
  if (arabic != null) return arabic;
  final upper = token.toUpperCase();
  if (!RegExp(r'^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$')
          .hasMatch(upper) ||
      upper.isEmpty) {
    return null;
  }
  var total = 0;
  for (var i = 0; i < upper.length; i++) {
    final value = _roman[upper[i]]!;
    final next = i + 1 < upper.length ? _roman[upper[i + 1]]! : 0;
    total += value < next ? -value : value;
  }
  return total;
}

/// Data TOC untuk prompt planner. `number` membantu model mencocokkan
/// "bab 3" dengan "III"; `section` membedakan Book I bab III dari Book III.
List<Map<String, Object?>> chatTocData(List<ChatChapterInfo> toc) => [
  for (final c in toc)
    {
      'id': c.id,
      if (c.section != null && c.section!.isNotEmpty) 'section': c.section,
      'title': c.title,
      'number': ?chatChapterNumber(c.title),
      'chars': c.chars,
    },
];

/// ID bab dari model: harus ada di TOC, unik, maksimal [max].
List<int> chatChapterIds(Object? raw, Iterable<int> known, {int max = 64}) {
  if (raw == null) return const [];
  final ids = known.toSet();
  if (raw is! List ||
      raw.length > max ||
      raw.any((id) => id is! int || !ids.contains(id)) ||
      raw.toSet().length != raw.length) {
    throw const FormatException('ID bab dari model tidak valid');
  }
  return raw.cast<int>();
}

/// Label bab untuk prompt/sitasi: "Book I › III: Of Providence".
String chatChapterLabel(ChatChapterInfo c) {
  final section = c.section;
  if (section == null || section.isEmpty) return c.title;
  final last = section.split(' › ').last;
  return '$last › ${c.title}';
}

const _romanLiterals = {
  1: 'i', 2: 'ii', 3: 'iii', 4: 'iv', 5: 'v', 6: 'vi', 7: 'vii', 8: 'viii', //
  9: 'ix', 10: 'x', 11: 'xi', 12: 'xii', 13: 'xiii', 14: 'xiv', 15: 'xv',
  16: 'xvi', 17: 'xvii', 18: 'xviii', 19: 'xix', 20: 'xx', 21: 'xxi',
  22: 'xxii', 23: 'xxiii', 24: 'xxiv', 25: 'xxv', 26: 'xxvi', 27: 'xxvii',
  28: 'xxviii', 29: 'xxix', 30: 'xxx',
};

/// "bab III"/"chapter 3" tanpa Book/bagian, sementara nomor itu ada di beberapa
/// section dan posisi baca tidak menentukan: kembalikan label section kandidat
/// supaya aplikasi bertanya, bukan menebak. Kosong = tidak ambigu.
List<String> chatAmbiguousSections(
  String question,
  List<int> chosenIds,
  List<ChatChapterInfo> toc, {
  int? readingChapterId,
}) {
  final byId = {for (final c in toc) c.id: c};
  final chosen = [for (final id in chosenIds) ?byId[id]];
  if (chosen.isEmpty) return const [];
  final numbers = chosen.map((c) => chatChapterNumber(c.title)).toSet();
  if (numbers.length != 1 || numbers.single == null) return const [];
  final number = numbers.single!;
  final q = question.toLowerCase();
  final roman = _romanLiterals[number];
  final bare = RegExp(
    r'\b(bab|chapter|ch\.?)\s*(' +
        number.toString() +
        (roman == null ? '' : '|$roman') +
        r')\b',
  );
  if (!bare.hasMatch(q)) return const [];
  if (RegExp(r'\b(book|buku|part|bagian|jilid)\s*[ivx\d]+').hasMatch(q)) {
    return const [];
  }
  final sections = <String>{};
  for (final c in toc) {
    if (chatChapterNumber(c.title) == number) sections.add(c.section ?? '');
  }
  if (sections.length <= 1) return const [];
  final reading = readingChapterId == null ? null : byId[readingChapterId];
  if (reading != null && chosen.every((c) => c.section == reading.section)) {
    return const [];
  }
  return [
    for (final s in sections)
      s.isEmpty ? '(tanpa bagian)' : s.split(' › ').last,
  ];
}
