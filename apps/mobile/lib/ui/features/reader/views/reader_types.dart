import '../../../../data/repositories/reading_progress_repository.dart';
import '../../../../domain/book_search.dart';
import '../../../../domain/models/book_search.dart';

enum ReaderSheet { toc, menu, aa }

/// Mode Cari kata di reader: hasil yang dibuka ([hits] urut baca, tiap hit
/// bareng judul babnya), [index] hasil yang lagi tampil, [back] posisi baca
/// sebelum nyari.
class SearchMode {
  SearchMode({
    required this.raw,
    required this.query,
    required this.hits,
    required this.truncated,
    required this.back,
  });

  final String raw;
  final BookSearchQuery query;
  final List<({BookSearchHit hit, String chapter})> hits;
  final bool truncated;
  final ReadingPosition? back;
  int index = 0;
}

/// Yang perlu diketahui [_ChapterText] soal mode cari: kata apa yang
/// di-stabilo, dan paragraf mana yang lagi dibuka.
class SearchMarks {
  const SearchMarks({
    required this.query,
    required this.chapterId,
    required this.paragraph,
  });

  final BookSearchQuery query;
  final int chapterId;
  final int paragraph;
}

/// Titik di chapter: indeks paragraf + bagiannya yang udah lewat garis atas.
typedef Spot = ({int index, double offset});
