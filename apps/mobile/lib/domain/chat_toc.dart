/// The book's real table of contents for Ngobrol planning: chapter identity from
/// `chapters.id`, the real TOC label, the parent section ("Discourses › Book I"),
/// and size. The model picks chapters by `id`; the app validates instead of trusting.
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

/// Roman/Arabic number at the start of a label ("III: Of…", "XXIX.", "Chapter 7") → 7.
/// Null when there is no leading number.
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

/// TOC data for the planner prompt. `number` helps the model match "bab 3" with
/// "III"; `section` tells Book I chapter III from Book III.
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

/// Chapter IDs from the model: must be in the TOC, unique, at most [max].
/// A number inside a string ("4") is accepted; IDs outside the TOC or duplicated are rejected.
List<int> chatChapterIds(Object? raw, Iterable<int> known, {int max = 64}) {
  if (raw == null) return const [];
  final ids = known.toSet();
  if (raw is! List || raw.length > max) {
    throw const FormatException('ID bab dari model tidak valid');
  }
  final parsed = [
    for (final id in raw)
      switch (id) {
        int n => n,
        String s when int.tryParse(s.trim()) != null => int.parse(s.trim()),
        _ => throw const FormatException('ID bab dari model tidak valid'),
      },
  ];
  if (parsed.any((id) => !ids.contains(id)) ||
      parsed.toSet().length != parsed.length) {
    throw const FormatException('ID bab dari model tidak valid');
  }
  return parsed;
}

/// Chapter label for prompts/citations: "Book I › III: Of Providence".
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

/// "bab III"/"chapter 3" without a Book/section, while that number exists in several
/// sections and the reading position doesn't decide: returns the candidate section
/// labels so the app asks instead of guessing. Empty = not ambiguous.
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
