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
  final flat = _flattenOutline(outline, totalPages: totalPages);
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

  // Remove duplicate block indices (two bookmarks pointing to same block)
  final seen = <int>{};
  final deduped = <_Boundary>[];
  for (final b in boundaries) {
    if (seen.add(b.blockIndex)) deduped.add(b);
  }

  if (deduped.length < 2) return const [];
  return deduped;
}

/// Flattens the outline tree selecting the most useful level.
/// Returns `List<({String title, int? pageNumber, String? section})>`
List<({String title, int? pageNumber, String? section})> _flattenOutline(
  List<PdfOutlineEntry> nodes, {
  required int totalPages,
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

  for (final node in nodes) {
    final validDest =
        node.pageNumber != null &&
        node.pageNumber! >= 1 &&
        node.pageNumber! <= totalPages;

    if (allPartsOrBooks && node.children.isNotEmpty) {
      // Treat this node as a section and use children as actual chapters
      final childResults = _flattenOutline(
        node.children,
        totalPages: totalPages,
        parentTitle: node.title,
        depth: depth + 1,
      );
      result.addAll(childResults);
    } else if (node.children.isNotEmpty && !validDest) {
      // Structural parent without destination – use children
      final childResults = _flattenOutline(
        node.children,
        totalPages: totalPages,
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

PdfParsedBook _assembleChapters(
  List<PdfLocatedBlock> blocks,
  List<_Boundary> boundaries,
) {
  if (boundaries.isEmpty) {
    // Everything in one chapter
    return _buildSingleChapter(blocks, 'Bagian 1');
  }

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

    final title = _resolveTitle(b.title, paragraphs);
    final chapter = ParsedChapter(
      title: title,
      section: b.section,
      paragraphs: paragraphs,
      groups: assignGroups(paragraphs),
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
