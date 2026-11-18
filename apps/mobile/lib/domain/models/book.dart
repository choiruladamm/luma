import 'markdown_shelf.dart';

/// Where a book came from (docs/import-formats.md). Stored as the enum name
/// (`textEnum`), so adding a value doesn't change the schema. Older binaries don't
/// know `pdf`: don't restore a backup containing PDF books into an app version
/// from before PDF import.
enum SourceType { epub, markdown, pdf }

/// Kind of block in a chapter. Heading and sceneBreak have no group and can't be tapped.
enum ParagraphType { paragraph, heading, sceneBreak }

/// One block from parsing a chapter, before it gets a group.
typedef RawParagraph = ({ParagraphType type, String text});

/// One book on the shelf.
class ShelfBook {
  const ShelfBook({
    required this.id,
    required this.title,
    required this.author,
    required this.coverName,
    required this.opened,
    required this.createdAt,
    this.progress = 0,
    this.finished = false,
    this.chapter = 1,
    this.chapterCount = 1,
    this.markdown,
  });

  final int id;
  final String title;
  final String? author;

  /// Cover file name in `covers/`; null = default cover.
  final String? coverName;

  /// Has been opened before (the "Baru" sticker goes away).
  final bool opened;

  /// When it was imported.
  final DateTime createdAt;

  /// Reading percentage 0..1 from the saved position (docs/architecture.md).
  final double progress;

  /// The saved position is at the end of the last paragraph of the last chapter:
  /// the end-of-book screen has been opened.
  final bool finished;

  /// Chapter of the saved position (1-based order) out of [chapterCount] chapters.
  final int chapter, chapterCount;

  /// Chapters imported so far + reading position; null for EPUB.
  final MarkdownShelf? markdown;
}

extension ShelfBookLabels on ShelfBook {
  /// Title that looks like a file name (no spaces, long): shown smaller and
  /// broken per character in the book Info sheet.
  bool get titleLooksLikeFileName => !title.contains(' ') && title.length >= 16;
}

/// Shelf order (menu "Urutin pake"). Defaults to [lastOpened].
enum ShelfSort { lastOpened, title, added }

/// Shelf layout: card grid or row list. Defaults to [grid].
enum ShelfView { grid, list }

/// Contents of the book Info sheet that shelf rows don't carry.
class BookInfo {
  const BookInfo({
    required this.lastOpenedAt,
    required this.createdAt,
    required this.fileName,
    required this.fileBytes,
    required this.translated,
    this.originalTitle,
    this.originalAuthor,
    this.epubCoverName,
    this.useDefaultCover = false,
  });

  /// The EPUB's original title/author; null = never edited.
  final String? originalTitle, originalAuthor;

  /// Raw `coverName` (kept even when the default cover is used).
  final String? epubCoverName;
  final bool useDefaultCover;

  final DateTime? lastOpenedAt;
  final DateTime createdAt;
  final String? fileName;

  /// EPUB size in Documents; null when the file doesn't exist.
  final int? fileBytes;

  /// Paragraphs already explained across the whole book.
  final int translated;
}

class ChapterInfo {
  const ChapterInfo({
    required this.id,
    required this.title,
    required this.charOffset,
    required this.chars,
  });

  final int id;
  final String title;

  /// Characters before this chapter and this chapter's length, for the percentage.
  final int charOffset;
  final int chars;
}

/// The book being read: title + chapter list in `sortOrder`.
class ReaderBook {
  const ReaderBook({
    required this.id,
    required this.title,
    required this.totalChars,
    required this.chapters,
    this.contentRevision = 1,
  });

  final int id;
  final int contentRevision;
  final String title;
  final int totalChars;
  final List<ChapterInfo> chapters;
}

class ReaderParagraph {
  const ReaderParagraph({
    required this.index,
    required this.groupIndex,
    required this.type,
    required this.text,
  });

  final int index;

  /// Null for headings and scene breaks.
  final int? groupIndex;
  final ParagraphType type;
  final String text;
}

/// Recap for the end-of-book screen (board 12 Akhir buku).
class BookEnd {
  const BookEnd({
    required this.author,
    required this.coverName,
    required this.readingSeconds,
    required this.translated,
  });

  final String? author;
  final String? coverName;

  /// Total active reading time.
  final int readingSeconds;

  /// Paragraphs already explained across the whole book.
  final int translated;
}
