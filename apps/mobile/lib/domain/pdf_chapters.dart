import 'package:luma/domain/grouping.dart';
import 'package:luma/domain/models/book.dart';
import 'package:luma/domain/pdf_layout.dart';

// ---------------------------------------------------------------------------
// Public input types (plain Dart – no pdfrx dependency)
// ---------------------------------------------------------------------------

/// One node from a PDF outline (bookmark tree).  [dest] is null when the node
/// is a structural parent (e.g. "Part I") with no direct page target.
class PdfOutlineEntry {
  const PdfOutlineEntry({
    required this.title,
    required this.pageNumber,
    this.children = const [],
  });

  final String title;

  /// 1-based page number; null means the bookmark has no valid destination.
  final int? pageNumber;
  final List<PdfOutlineEntry> children;
}

// ---------------------------------------------------------------------------
// Output – same ParsedChapter used by EPUB importer
// ---------------------------------------------------------------------------

class ParsedChapter {
  const ParsedChapter({
    required this.title,
    required this.paragraphs,
    required this.groups,
    required this.charOffset,
    this.section,
  });

  final String title;
  final String? section;
  final List<RawParagraph> paragraphs;
  final List<int?> groups;
  final int charOffset;

  int get charCount => paragraphs.fold(0, (n, p) => n + p.text.length);
}

typedef PdfParsedBook = ({List<ParsedChapter> chapters, int totalChars});

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

/// Splits [blocks] (output of [PdfLayoutEngine.processToBlocks]) into
/// [ParsedChapter]s using three fallback strategies in priority order:
///
/// 1. **Outline** – validated PDF bookmarks, choosing the best hierarchy level.
/// 2. **Headings** – strong `Chapter/Bab N` or large-font headings inside the
///    blocks, when outline is absent/unusable.
/// 3. **Page fallback** – every ~[fallbackPageSize] pages, labelled "Bagian N".
PdfParsedBook splitPdfChapters(
  List<PdfLocatedBlock> blocks, {
  List<PdfOutlineEntry> outline = const [],
  int totalPages = 0,
  int fallbackPageSize = 20,
}) {
  if (blocks.isEmpty) {
    return (chapters: const [], totalChars: 0);
  }

  final boundaries = _chooseBoundaries(
    blocks: blocks,
    outline: outline,
    totalPages: totalPages,
    fallbackPageSize: fallbackPageSize,
  );

  return _assembleChapters(blocks, boundaries);
}

// ---------------------------------------------------------------------------
// Step 1 – choose chapter boundaries
// ---------------------------------------------------------------------------

class _Boundary {
  const _Boundary({
    required this.blockIndex,
    required this.title,
    this.section,
  });
  final int blockIndex; // first block index of this chapter
  final String title;
  final String? section;
}

List<_Boundary> _chooseBoundaries({
  required List<PdfLocatedBlock> blocks,
  required List<PdfOutlineEntry> outline,
  required int totalPages,
  required int fallbackPageSize,
}) {
  // --- Strategy 1: outline ---
  final outlineBoundaries = _boundariesFromOutline(blocks, outline);
  if (outlineBoundaries.length >= 2) return outlineBoundaries;

  // --- Strategy 2: headings ---
  final headingBoundaries = _boundariesFromHeadings(blocks);
  if (headingBoundaries.length >= 2) return headingBoundaries;

  // --- Strategy 3: page fallback ---
  return _boundariesFromPageFallback(blocks, totalPages, fallbackPageSize);
}

// ---------------------------------------------------------------------------
// Strategy 1 – outline
// ---------------------------------------------------------------------------

/// Returns validated boundaries from [outline], or empty list when unusable.
List<_Boundary> _boundariesFromOutline(
  List<PdfLocatedBlock> blocks,
  List<PdfOutlineEntry> outline,
) {
  if (outline.isEmpty) return const [];

  final totalPages = blocks.isEmpty
      ? 0
      : blocks.map((b) => b.pageNumber).reduce((a, b) => a > b ? a : b);

  // Flatten outline choosing the best level
  final flat = _flattenOutline(
    outline,
    totalPages: totalPages,
    endPage: totalPages + 1,
  );
  if (flat.isEmpty) return const [];

  // Validate: at least 2 entries, page numbers in ascending order
  if (flat.length < 2) return const [];

  final boundaries = <_Boundary>[];
  for (final entry in flat) {
    if (entry.pageNumber == null) continue;
    final blockIdx = _firstBlockOnOrAfterPage(blocks, entry.pageNumber!);
    if (blockIdx < 0) continue;
    // Try to find a heading in the first few blocks that matches bookmark title
    final adjustedIdx = _matchHeadingNearBlock(blocks, blockIdx, entry.title);
    boundaries.add(
      _Boundary(
        blockIndex: adjustedIdx,
        title: entry.title,
        section: entry.section,
      ),
    );
  }

  if (boundaries.isEmpty) return const [];

  // Bookmarks are not always in page order; chapters are slices of the block
  // list, so boundaries must be ascending (stable sort keeps outline order for
  // equal targets). Duplicate block indices (two bookmarks, same block) keep
  // the first.
  // (List.sort is not stable, so the outline position breaks ties.)
  final sorted = [for (final (i, b) in boundaries.indexed) (i, b)]
    ..sort((a, b) {
      final c = a.$2.blockIndex.compareTo(b.$2.blockIndex);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  final seen = <int>{};
  final deduped = <_Boundary>[];
  for (final (_, b) in sorted) {
    if (seen.add(b.blockIndex)) deduped.add(b);
  }

  if (deduped.length < 2) return const [];
  return deduped;
}

/// An outline entry spanning more pages than this, with children, is split
/// into its children.
const _containerPages = 60;

/// Flattens the outline tree selecting the most useful level.
/// Returns `List<({String title, int? pageNumber, String? section})>`
List<({String title, int? pageNumber, String? section})> _flattenOutline(
  List<PdfOutlineEntry> nodes, {
  required int totalPages,
  required int endPage,
  String? parentTitle,
  int depth = 0,
}) {
  if (nodes.isEmpty) return const [];

  // Check if this level contains only "Part"/"Book" parents
  final allPartsOrBooks = nodes.every(
    (n) => RegExp(
      r'^(part|book|volume|section)\s',
      caseSensitive: false,
    ).hasMatch(n.title.trim()),
  );

  final result = <({String title, int? pageNumber, String? section})>[];

  for (final (i, node) in nodes.indexed) {
    final validDest =
        node.pageNumber != null &&
        node.pageNumber! >= 1 &&
        node.pageNumber! <= totalPages;
    // Where this node's pages end: the next sibling's start, else the parent's.
    final nextPage = nodes
        .skip(i + 1)
        .map((n) => n.pageNumber)
        .firstWhere((p) => p != null && p >= 1, orElse: () => null);
    final nodeEnd = nextPage ?? endPage;
    // A top-level entry that swallows a big stretch of the book while having
    // several children (e.g. "Letters" holding 124 letters) is a container:
    // the children are the chapters.
    final oversize =
        validDest &&
        node.children.length >= 3 &&
        nodeEnd - node.pageNumber! > _containerPages;

    if ((allPartsOrBooks || oversize) && node.children.isNotEmpty) {
      // Treat this node as a section and use children as actual chapters
      final childResults = _flattenOutline(
        node.children,
        totalPages: totalPages,
        endPage: nodeEnd,
        parentTitle: node.title,
        depth: depth + 1,
      );
      result.addAll(childResults);
    } else if (node.children.isNotEmpty && !validDest) {
      // Structural parent without destination – use children
      final childResults = _flattenOutline(
        node.children,
        totalPages: totalPages,
        endPage: nodeEnd,
        parentTitle: parentTitle,
        depth: depth + 1,
      );
      result.addAll(childResults);
    } else {
      result.add((
        title: node.title,
        pageNumber: validDest ? node.pageNumber : null,
        section: parentTitle,
      ));
    }
  }

  return result;
}

int _firstBlockOnOrAfterPage(List<PdfLocatedBlock> blocks, int page) {
  for (var i = 0; i < blocks.length; i++) {
    if (blocks[i].pageNumber >= page) return i;
  }
  return -1;
}

/// Looks at the next [lookahead] blocks from [startIdx] and returns the index
/// of a heading block whose text matches [title] (case-insensitive prefix),
/// or [startIdx] if no match.
int _matchHeadingNearBlock(
  List<PdfLocatedBlock> blocks,
  int startIdx,
  String title, {
  int lookahead = 5,
}) {
  final normalTitle = title.toLowerCase().trim();
  final end = (startIdx + lookahead).clamp(0, blocks.length);
  for (var i = startIdx; i < end; i++) {
    final b = blocks[i];
    if (b.type == ParagraphType.heading) {
      final blockText = b.text.toLowerCase().trim();
      if (blockText.startsWith(normalTitle) ||
          normalTitle.startsWith(blockText)) {
        return i;
      }
    }
  }
  return startIdx;
}

// ---------------------------------------------------------------------------
// Strategy 2 – headings
// ---------------------------------------------------------------------------

List<_Boundary> _boundariesFromHeadings(List<PdfLocatedBlock> blocks) {
  final boundaries = <_Boundary>[];

  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    if (b.type != ParagraphType.heading) continue;
    if (!_isStrongHeading(b.text)) continue;
    boundaries.add(_Boundary(blockIndex: i, title: b.text.trim()));
  }

  if (boundaries.length < 2) return const [];
  return boundaries;
}

/// Returns true if [text] looks like a chapter heading (not just any heading).
bool _isStrongHeading(String text) {
  final t = text.trim();
  // Pattern: "Chapter N", "Bab N", "Part N", etc.
  if (RegExp(
    r'^(chapter|bab|part|bagian|act|scene|section|volume|livre)\s+(\d+|[ivxlcdm]+)',
    caseSensitive: false,
  ).hasMatch(t)) {
    return true;
  }
  // All-caps short heading that looks like a chapter title
  if (t == t.toUpperCase() && t.length <= 60 && t.split(' ').length <= 8) {
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Strategy 3 – page fallback
// ---------------------------------------------------------------------------

List<_Boundary> _boundariesFromPageFallback(
  List<PdfLocatedBlock> blocks,
  int totalPages,
  int fallbackPageSize,
) {
  if (blocks.isEmpty) {
    return [const _Boundary(blockIndex: 0, title: 'Bagian 1')];
  }

  final maxPage = blocks
      .map((b) => b.pageNumber)
      .reduce((a, b) => a > b ? a : b);
  final effectiveTotalPages = totalPages > 0 ? totalPages : maxPage;

  if (effectiveTotalPages <= fallbackPageSize) {
    return [const _Boundary(blockIndex: 0, title: 'Bagian 1')];
  }

  final boundaries = <_Boundary>[];
  var sectionNum = 1;
  var nextBoundaryPage = 1;

  for (var i = 0; i < blocks.length; i++) {
    if (blocks[i].pageNumber >= nextBoundaryPage) {
      boundaries.add(_Boundary(blockIndex: i, title: 'Bagian $sectionNum'));
      sectionNum++;
      nextBoundaryPage += fallbackPageSize;
    }
  }

  if (boundaries.isEmpty) {
    return [const _Boundary(blockIndex: 0, title: 'Bagian 1')];
  }

  return boundaries;
}

// ---------------------------------------------------------------------------
// Step 2 – assemble ParsedChapters from boundaries
// ---------------------------------------------------------------------------

const _minFrontMatterChars = 300;

PdfParsedBook _assembleChapters(
  List<PdfLocatedBlock> blocks,
  List<_Boundary> boundaries,
) {
  if (boundaries.isEmpty) {
    // Everything in one chapter
    return _buildSingleChapter(blocks, 'Bagian 1');
  }

  // Text before the first boundary (preface, unbookmarked front matter) is
  // kept as its own chapter when it is more than a title page.
  final first = boundaries.first.blockIndex;
  if (first > 0 &&
      blocks
              .take(first)
              .where((b) => b.type == ParagraphType.paragraph)
              .fold<int>(0, (n, b) => n + b.text.length) >=
          _minFrontMatterChars) {
    boundaries = [
      const _Boundary(blockIndex: 0, title: 'Pembuka'),
      ...boundaries,
    ];
  }

  final titles = [
    for (final b in boundaries)
      if (b.title.trim().length >= 4) b.title.trim().toLowerCase(),
  ];

  final chapters = <ParsedChapter>[];
  int offset = 0;

  for (var i = 0; i < boundaries.length; i++) {
    final b = boundaries[i];
    final endIdx = i + 1 < boundaries.length
        ? boundaries[i + 1].blockIndex
        : blocks.length;

    final chapterBlocks = blocks.sublist(b.blockIndex, endIdx);
    final paragraphs = _blocksToRawParagraphs(chapterBlocks);

    // Skip empty chapters and TOC/index pages
    if (!_isContentChapter(paragraphs, chapterBlocks)) continue;
    if (_listsChapterTitles(paragraphs, titles, b.title)) continue;
    if (_dropLabel.hasMatch(b.title.trim()) &&
        paragraphs.fold<int>(0, (n, p) => n + p.text.length) <
            _tinyFrontMatterChars) {
      continue;
    }

    final title = _resolveTitle(b.title, paragraphs);
    final body = _withoutTocRuns(
      _withoutTitleHeadings(paragraphs, title),
      titles,
      title,
    );
    final chapter = ParsedChapter(
      title: title,
      section: b.section,
      paragraphs: body,
      groups: assignGroups(body),
      charOffset: offset,
    );
    chapters.add(chapter);
    offset += chapter.charCount;
  }

  if (chapters.isEmpty) {
    // Fallback: nothing was content; keep everything in one chapter
    return _buildSingleChapter(blocks, 'Bagian 1');
  }

  return (chapters: chapters, totalChars: offset);
}

PdfParsedBook _buildSingleChapter(List<PdfLocatedBlock> blocks, String title) {
  final paragraphs = _blocksToRawParagraphs(blocks);
  final chapter = ParsedChapter(
    title: title,
    paragraphs: paragraphs,
    groups: assignGroups(paragraphs),
    charOffset: 0,
  );
  return (chapters: [chapter], totalChars: chapter.charCount);
}

List<RawParagraph> _blocksToRawParagraphs(List<PdfLocatedBlock> blocks) {
  return [for (final b in blocks) b.toRawParagraph()];
}

/// A contents list sitting inside a chapter that has no bookmark of its own
/// (ebook PDFs put it after the copyright page): a run of 4+ consecutive short
/// blocks where most are titles of the book's chapters. The run goes; the text
/// around it stays.
List<RawParagraph> _withoutTocRuns(
  List<RawParagraph> paragraphs,
  List<String> titles,
  String ownTitle,
) {
  if (titles.length < 4 || paragraphs.length < 4) return paragraphs;
  String norm(String t) => t
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
  final all = [for (final t in titles) norm(t)];
  final own = norm(ownTitle);
  bool short(RawParagraph p) =>
      p.type != ParagraphType.sceneBreak &&
      p.text.trim().length <= 100 &&
      !RegExp(r'[.!?"”]$').hasMatch(p.text.trim());
  bool isTitle(RawParagraph p) {
    final n = norm(p.text);
    return n.length >= 4 &&
        all.any((c) => c.length >= 4 && c != own && (n == c || n.endsWith(c)));
  }

  final drop = <int>{};
  var i = 0;
  while (i < paragraphs.length) {
    if (!short(paragraphs[i])) {
      i++;
      continue;
    }
    var j = i;
    var hits = 0;
    while (j < paragraphs.length && short(paragraphs[j])) {
      if (isTitle(paragraphs[j])) hits++;
      j++;
    }
    if (hits >= 4 && hits >= (j - i) * 0.4) {
      for (var k = i; k < j; k++) {
        drop.add(k);
      }
    }
    i = j;
  }
  if (drop.isEmpty) return paragraphs;
  final rest = [
    for (final (k, p) in paragraphs.indexed)
      if (!drop.contains(k)) p,
  ];
  return rest.any((p) => p.type == ParagraphType.paragraph) ? rest : paragraphs;
}

/// The reader already shows the chapter title, so a heading at the top of the
/// chapter that just repeats it ("1", "The Surprising Power…" under "1 The
/// Surprising Power…") is dropped. Only the first 3 blocks, only headings
/// contained in the title, and only if body text remains.
List<RawParagraph> _withoutTitleHeadings(
  List<RawParagraph> paragraphs,
  String title,
) {
  String norm(String t) =>
      t.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
  final nt = norm(title);
  if (nt.isEmpty) return paragraphs;
  var drop = 0;
  while (drop < 3 &&
      drop < paragraphs.length &&
      paragraphs[drop].type == ParagraphType.heading) {
    final h = norm(paragraphs[drop].text);
    if (h.isEmpty || !nt.contains(h)) break;
    drop++;
  }
  if (drop == 0) return paragraphs;
  final rest = paragraphs.sublist(drop);
  return rest.any((p) => p.type == ParagraphType.paragraph) ? rest : paragraphs;
}

/// A table of contents with no page numbers: most of its short lines are the
/// titles of the book's own chapters. Judged by structure (the lines quote the
/// bookmarks), not by a "Contents" label.
bool _listsChapterTitles(
  List<RawParagraph> paragraphs,
  List<String> titles,
  String ownTitle,
) {
  if (titles.length < 4) return false;
  final lines = paragraphs
      .where((p) => p.type == ParagraphType.paragraph)
      .toList();
  // Bookmarks say "1 | Title", the printed contents "1 Title": compare words.
  String norm(String t) => t
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
  titles = [for (final t in titles) norm(t)];
  final own = norm(ownTitle);

  // Lines merged into one or two paragraphs: a short chapter whose text is
  // mostly the titles of other chapters.
  final all = norm(lines.map((p) => p.text).join(' '));
  if (all.length <= 3000) {
    final found = {
      for (final c in titles)
        if (c != own && all.contains(c)) c,
    };
    if (found.length >= 4 &&
        found.fold<int>(0, (n, c) => n + c.length) >= all.length * 0.5) {
      return true;
    }
  }
  if (lines.length < 4) return false;
  final hits = lines.where((p) {
    final t = p.text.trim().toLowerCase();
    final n = norm(t);
    return n.length <= 120 &&
        titles.any((c) => c != own && (n == c || n.endsWith(c)));
  }).length;
  return hits >= lines.length * 0.6;
}

/// Returns false for chapters that have no body text paragraphs or look like
/// a table of contents / index page (high ratio of numeric-trailing lines).
bool _isContentChapter(
  List<RawParagraph> paragraphs,
  List<PdfLocatedBlock> blocks,
) {
  final bodyParagraphs = paragraphs
      .where((p) => p.type == ParagraphType.paragraph)
      .toList();
  if (bodyParagraphs.isEmpty) return false;

  // TOC/index detection: if the majority of body paragraphs end with a plain
  // number (after dots/spaces) and blocks are short, treat as non-content.
  // Require strong structural evidence; don't discard on ambiguous cases.
  if (bodyParagraphs.length >= 3) {
    final tocLike = bodyParagraphs.where((p) {
      final t = p.text.trim();
      // Lines like "Chapter 1 .......... 12" or "Introduction 5"
      return RegExp(r'[\.\s]+\d+\s*$').hasMatch(t) && t.length < 100;
    }).length;
    if (tocLike >= bodyParagraphs.length * 0.80) return false;
  }

  return true;
}

/// Uses the chapter's first heading (if any) to override or clean the
/// bookmark title, following the same logic as the EPUB extractor.
String _resolveTitle(String bookmarkTitle, List<RawParagraph> paragraphs) {
  final heading = paragraphs
      .take(3)
      .where((p) => p.type == ParagraphType.heading)
      .map((p) => p.text.trim())
      .firstOrNull;

  if (heading == null || heading.isEmpty) return bookmarkTitle.trim();

  final bt = bookmarkTitle.trim().toLowerCase();
  final ht = heading.toLowerCase();

  // If bookmark title starts with the heading (or vice-versa), prefer the
  // longer/more descriptive one; otherwise keep the bookmark title.
  if (bt.startsWith(ht) || ht.startsWith(bt)) {
    return bt.length >= ht.length ? bookmarkTitle.trim() : heading;
  }

  return bookmarkTitle.trim();
}

// ---------------------------------------------------------------------------
// Whole-document glue (runs in an isolate, pure Dart)
// ---------------------------------------------------------------------------

/// Versi logika layout + pecah bab PDF, disimpan di `books.parserVersion`.
/// Naik = re-import dari `$hash.pdf` + hapus `ai_results` buku itu (indeks
/// paragraf/grup bisa geser). Terpisah dari `parserVersion` EPUB, jadi tuning
/// PDF gak maksa re-import EPUB. Re-import UI belum ada.
const pdfParserVersion = 1;

/// [pages] indeks 0 = halaman 1. [heading] = heading pertama di halaman 1
/// (kandidat judul buku), null kalau gak ada.
typedef PdfLayoutResult = ({
  List<ParsedChapter> chapters,
  int totalChars,
  String? heading,
});

/// Short paragraph blocks that are not text: leftovers of figures and
/// diagrams ("nn nn n", "r"), stray punctuation, bare page/list numbers.
/// Only Latin-script text is judged by the vowel rule; other scripts are kept.
bool _isJunkBlock(PdfLocatedBlock b) {
  if (b.type != ParagraphType.paragraph) return false;
  final t = b.text.trim();
  if (t.length > 40) return false;
  if (RegExp(r'^[\W_]*$').hasMatch(t)) return true; // punctuation only
  if (RegExp(r'^\d{1,4}[.)]?$').hasMatch(t)) return true; // "20", "3."
  final letters = RegExp(r'\p{L}', unicode: true).allMatches(t);
  if (letters.any((m) => m.group(0)!.codeUnitAt(0) > 0x24F)) return false;
  // Real short text has a word of 2+ letters with a vowel ("No.", "Yes").
  return !RegExp(
    r'\b[a-z]*[aeiouy][a-z]*\b',
    caseSensitive: false,
  ).allMatches(t).any((m) => m.group(0)!.length >= 2);
}

/// A title page often prints the title in body size and all caps ("LETTERS
/// FROM A STOIC"), so the heading found may be only its tail ("FROM A STOIC").
/// When the first printed line of the book contains the heading and is itself
/// a short all-caps line, that line is the full title. Needs a heading to
/// start from: an all-caps first line alone ("AN IMPRINT OF …") proves nothing.
String? _titleCandidate(String? heading, List<List<PdfLine>> pages) {
  if (heading == null) return null;
  final first = pages.where((p) => p.isNotEmpty).firstOrNull?.first.text.trim();
  if (first == null ||
      first.length > 60 ||
      first.length <= heading.length ||
      first != first.toUpperCase() ||
      !first.toLowerCase().contains(heading.toLowerCase())) {
    return heading;
  }
  return first;
}

/// Bookmarked front matter that is only a label page: dropped when tiny.
final _dropLabel = RegExp(
  r'^(cover|title page|half title|copyright( page)?|contents|table of contents|'
  r'halaman judul|hak cipta|daftar isi)$',
  caseSensitive: false,
);
const _tinyFrontMatterChars = 1500;

final _frontMatterLabel = RegExp(
  r'^(title page|half title|copyright|dedication|contents|table of contents|'
  r'acknowledg(e)?ments?|epigraph|about the author|also by|cover|halaman judul|'
  r'daftar isi|hak cipta|kata pengantar|prakata|ebook isbn.*)\b',
  caseSensitive: false,
);

/// [pages] = lines per page (index 0 = page 1; empty = no text). Lines, not
/// glyphs: the service builds them page by page so the glyphs of a 1000-page
/// book never sit in memory (or cross the isolate boundary) all at once.
PdfLayoutResult layoutPdf(
  List<List<PdfLine>> pages,
  List<PdfOutlineEntry> outline, {
  PdfLayoutEngine engine = const PdfLayoutEngine(),
}) {
  final lines = [for (final page in pages) ...page];
  final body = engine.computeBodyFontSize(lines);
  final kept = engine.filterHeadersFootersAndFootnotes(
    lines,
    totalPages: pages.length,
    bodyFontSize: body,
  );
  final blocks = [
    for (final b in engine.processToBlocks(kept, bodyFontSize: body))
      if (!_isJunkBlock(b)) b,
  ];
  final book = splitPdfChapters(
    blocks,
    outline: outline,
    totalPages: pages.length,
  );
  // ponytail: heading pertama di 5 halaman awal yang bukan label front matter
  // (sampul gambar = halaman 1 tanpa teks, judul ada di halaman judul), bukan
  // yang font-nya terbesar; cadangan sampai pdfrx punya API metadata.
  final heading = _titleCandidate(
    blocks
        .where(
          (b) =>
              b.pageNumber <= 5 &&
              b.type == ParagraphType.heading &&
              b.text.trim().length >= 3 &&
              b.text.trim().length <= 120 &&
              !_frontMatterLabel.hasMatch(b.text.trim()),
        )
        .firstOrNull
        ?.text
        .trim(),
    pages,
  );
  return (
    chapters: book.chapters,
    totalChars: book.totalChars,
    heading: heading,
  );
}
