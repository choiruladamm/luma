import '../../../../data/repositories/reading_progress_repository.dart';
import '../../../../domain/book_search.dart';
import '../../../../domain/models/book_search.dart';

enum ReaderSheet { toc, menu, aa }

/// Cari kata mode in the reader: the opened results ([hits] in reading order, each
/// hit together with its chapter title), [index] the result being shown, [back]
/// the reading position before searching.
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

/// What `_ChapterText` needs to know about search mode: which word is highlighted,
/// and which paragraph is open.
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

/// A point in a chapter: paragraph index + the part of it already past the top line.
typedef Spot = ({int index, double offset});
