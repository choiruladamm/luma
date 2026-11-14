/// Satu paragraf yang cocok.
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

  /// Null buat heading.
  final int? groupIndex;

  /// Cuplikan (±60 huruf kiri-kanan, "…" di sisi yang kepotong).
  final String snippet;

  /// Posisi kata cocok di [snippet]; `0..0` kalau gak ketemu di teks.
  final int matchStart;
  final int matchEnd;
}

/// Hasil satu bab, urut paragraf.
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

/// Hasil cari satu buku: bab urut buku, maksimal 500 paragraf.
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

  /// Cuma yang ditampilin (≤ 500 paragraf).
  final List<BookSearchChapter> chapters;

  /// Seluruh paragraf yang cocok, bisa > 500.
  final int total;

  /// Jumlah bab yang punya hasil.
  final int chapterCount;

  int get shown => chapters.fold(0, (n, c) => n + c.hits.length);

  /// Ada yang gak ditampilin ("Kebanyakan, coba kata yang lebih spesifik").
  bool get truncated => total > shown;

  bool get isEmpty => total == 0;
}

extension BookSearchResultLabel on BookSearchResult {
  /// "68 hasil di 31 bab".
  String get countLabel => '$total hasil di $chapterCount bab';
}

/// Hasil yang di-tap di sheet Cari kata: reader lompat ke [hit], dan nyimpen
/// [result] buat navigator ↑ ↓.
typedef BookSearchPick = ({
  String query,
  BookSearchResult result,
  BookSearchHit hit,
});
