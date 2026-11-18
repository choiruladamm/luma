/// Stage of one group's Bedahin. Same time thresholds as the quick meaning.
enum BreakdownPhase {
  /// Waiting for the first token.
  waiting,

  /// Writing; a section whose marker has arrived already has a range.
  writing,

  /// Complete, valid, cached.
  done,

  /// 15 seconds without a token. The request keeps running.
  slow,

  /// Dropped / stalled midway; what already arrived stays.
  cut,

  /// Failed before any token, or the answer was invalid twice.
  failed,
}

/// Bedahin result for one group (docs/llm.md, Bedahin).
class Breakdown {
  const Breakdown({
    this.sections = const [],
    this.terms = const [],
    this.links = const [],
    this.practice,
  });

  /// 1–6 sections, one per argument step; their ranges consecutively cover `K1..Kn`.
  final List<BreakdownSection> sections;

  /// Tokoh & istilah. Empty = the block isn't shown.
  final List<BreakdownTerm> terms;

  /// Nyambung ke. Empty = the block isn't shown.
  final List<BreakdownLink> links;

  /// Praktekinnya gini. Null = the block isn't shown.
  final String? practice;
}

/// One argument step: translated sentences `K[from]..K[to]` (starting at 1, numbers
/// continue across the group's paragraphs).
class BreakdownSection {
  const BreakdownSection({
    required this.from,
    required this.to,
    this.title = '',
    this.meaning = '',
    this.logic = '',
  });

  final int from;
  final int to;

  /// Shown only when there are ≥ 2 sections.
  final String title;
  final String meaning;
  final String logic;
}

class BreakdownTerm {
  const BreakdownTerm({
    required this.label,
    this.exact,
    required this.explanation,
    this.sentence,
  });

  final String label;

  /// The exact words in the translation, for highlighting. Null = not found: the
  /// term is still shown, without a highlight.
  final String? exact;
  final String explanation;

  /// First sentence (`K`, starting at 1) containing [exact].
  final int? sentence;
}

class BreakdownLink {
  const BreakdownLink({this.chapter, required this.title, required this.why});

  /// Chapter number in the CHAPTER LIST (`B<n>`, starting at 1, in `sortOrder`). Null =
  /// continuation: the next group in the same chapter.
  final int? chapter;
  final String title;
  final String why;
}

/// Destination of the previewed Nyambung ke card: the first group of chapter [B<n>],
/// or the next group in the same chapter (continuation).
class BreakdownPeek {
  const BreakdownPeek({
    required this.group,
    required this.original,
    this.translations,
  });

  final ({int chapterId, int groupIndex}) group;

  /// The destination group's original text: always present, local.
  final List<String> original;

  /// Translation from the quick-meaning cache. Null = not explained yet.
  final List<String>? translations;
}
