/// One matching paragraph.
class BookSearchHit {
  const BookSearchHit({
    required this.chapterId,
    required this.paragraphIndex,
    required this.groupIndex,
    required this.snippet,
    required this.matchStart,
    required this.matchEnd,
  });

  final int chapterId;
  final int paragraphIndex;

  /// Null for headings.
  final int? groupIndex;

  /// Snippet (±60 letters on each side, "…" on the truncated side).
  final String snippet;

  /// Position of the matched word in [snippet]; `0..0` when not found in the text.
  final int matchStart;
  final int matchEnd;
}

/// Result for one chapter, in paragraph order.
class BookSearchChapter {
  const BookSearchChapter({
    required this.chapterId,
    required this.title,
    required this.sortOrder,
    required this.hits,
  });

  final int chapterId;
  final String title;
  final int sortOrder;
  final List<BookSearchHit> hits;
}

/// Result of searching one book: chapters in book order, at most 500 paragraphs.
class BookSearchResult {
  const BookSearchResult({
    required this.chapters,
    required this.total,
    required this.chapterCount,
  });

  static const empty = BookSearchResult(
    chapters: [],
    total: 0,
    chapterCount: 0,
  );

  /// Only what is shown (≤ 500 paragraphs).
  final List<BookSearchChapter> chapters;

  /// All matching paragraphs, may exceed 500.
  final int total;

  /// Number of chapters with results.
  final int chapterCount;

  int get shown => chapters.fold(0, (n, c) => n + c.hits.length);

  /// Some results aren't shown ("Kebanyakan, coba kata yang lebih spesifik").
  bool get truncated => total > shown;

  bool get isEmpty => total == 0;
}

extension BookSearchResultLabel on BookSearchResult {
  /// "68 hasil di 31 bab".
  String get countLabel => '$total hasil di $chapterCount bab';
}

/// The result tapped in the Cari kata sheet: the reader jumps to `hit` and keeps
/// `result` for the ↑ ↓ navigator.
typedef BookSearchPick = ({
  String query,
  BookSearchResult result,
  BookSearchHit hit,
});
