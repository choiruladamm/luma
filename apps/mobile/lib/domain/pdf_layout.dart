import 'dart:math' as math;

import 'models/book.dart';

/// Bounding rectangle for normalized page coordinates (origin at top-left, 0..1).
class PdfRectNormalized {
  const PdfRectNormalized({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  @override
  String toString() =>
      'PdfRect(l: ${left.toStringAsFixed(3)}, t: ${top.toStringAsFixed(3)}, w: ${width.toStringAsFixed(3)}, h: ${height.toStringAsFixed(3)})';
}

/// Raw glyph input extracted from a PDF page.
class PdfGlyph {
  const PdfGlyph({
    required this.char,
    required this.bounds,
    required this.pageNumber,
    this.fontHeight,
  });

  final String char;
  final PdfRectNormalized bounds;
  final int pageNumber;
  final double? fontHeight;

  double get effectiveFontHeight => fontHeight ?? bounds.height;
}

/// Extracted line of text with bounding geometry and font size statistics.
class PdfLine {
  const PdfLine({
    required this.text,
    required this.bounds,
    required this.pageNumber,
    required this.fontHeight,
    this.hasSuperscript = false,
  });

  final String text;
  final PdfRectNormalized bounds;
  final int pageNumber;
  final double fontHeight;
  final bool hasSuperscript;

  @override
  String toString() => 'PdfLine(p$pageNumber: "$text")';
}

/// A structured block of text tied to a page location and bounding box.
class PdfLocatedBlock {
  const PdfLocatedBlock({
    required this.type,
    required this.text,
    required this.pageNumber,
    required this.bounds,
  });

  final ParagraphType type;
  final String text;
  final int pageNumber;
  final PdfRectNormalized bounds;

  RawParagraph toRawParagraph() => (type: type, text: text);

  @override
  String toString() => 'PdfLocatedBlock($type, p$pageNumber: "$text")';
}

/// Pipeline processor that turns raw glyphs and page lines into structured text blocks.
class PdfLayoutEngine {
  static bool _hasTerminalPunctuation(String s) {
    if (s.isEmpty) return false;
    final last = s[s.length - 1];
    return last == '.' ||
        last == '?' ||
        last == '!' ||
        last == ':' ||
        last == '"' ||
        last == "'" ||
        last == '”' ||
        last == '’';
  }

  const PdfLayoutEngine({
    this.headerFooterMarginRatio = 0.08,
    this.headerFooterFrequencyThreshold = 0.30,
    this.headingFontScale = 1.20,
    this.footnoteFontScale = 0.85,
    this.paragraphGapScale = 1.50,
  });

  final double headerFooterMarginRatio;
  final double headerFooterFrequencyThreshold;
  final double headingFontScale;
  final double footnoteFontScale;
  final double paragraphGapScale;

  /// Cleans raw text: replaces ligatures, strips control characters, soft hyphens, zero-widths, normalizes NBSP.
  static String cleanText(String input) {
    if (input.isEmpty) return '';

    var s = input
        .replaceAll('\uFB00', 'ff')
        .replaceAll('\uFB01', 'fi')
        .replaceAll('\uFB02', 'fl')
        .replaceAll('\uFB03', 'ffi')
        .replaceAll('\uFB04', 'ffl')
        .replaceAll('\uFB05', 'ft')
        .replaceAll('\uFB06', 'st')
        .replaceAll('\u00AD', '') // soft hyphen
        .replaceAll('\u0000', '') // null character
        .replaceAll('\uFFFD', '') // replacement character
        .replaceAll('\u200B', '') // zero-width space
        .replaceAll('\u200C', '') // zero-width non-joiner
        .replaceAll('\u200D', '') // zero-width joiner
        .replaceAll('\uFEFF', '') // zero-width no-break space (BOM)
        .replaceAll('\u00A0', ' ') // non-breaking space
        .replaceAll('\u202F', ' '); // narrow no-break space

    return s;
  }

  /// Groups glyphs on a single page into ordered lines (top to bottom, left to right, baseline cluster).
  List<PdfLine> glyphsToLines(
    List<PdfGlyph> glyphs, {
    required int pageNumber,
  }) {
    if (glyphs.isEmpty) return const [];

    // Filter out invisible control glyphs while retaining spaces
    final valid = <PdfGlyph>[];
    for (final g in glyphs) {
      final c = cleanText(g.char);
      if (c.isNotEmpty || g.char == ' ') {
        valid.add(
          PdfGlyph(
            char: c.isEmpty ? ' ' : c,
            bounds: g.bounds,
            pageNumber: pageNumber,
            fontHeight: g.fontHeight,
          ),
        );
      }
    }

    if (valid.isEmpty) return const [];

    // Detect two-column layout on this page
    final columns = _detectColumns(valid);
    final lines = <PdfLine>[];

    for (final col in columns) {
      lines.addAll(_assembleColumnLines(col, pageNumber));
    }

    return lines;
  }

  List<List<PdfGlyph>> _detectColumns(List<PdfGlyph> glyphs) {
    if (glyphs.isEmpty) return const [];

    // Check if there is a distinct vertical column gap in the middle region
    final minX = glyphs.map((g) => g.bounds.left).reduce(math.min);
    final maxX = glyphs.map((g) => g.bounds.right).reduce(math.max);
    final width = maxX - minX;

    if (width <= 0.2) {
      // Too narrow to be multi-column
      return [glyphs];
    }

    // Build horizontal histogram to find gutter (excluding wide spanners)
    final bucketCount = 50;
    final buckets = List<int>.filled(bucketCount, 0);

    for (final g in glyphs) {
      if (g.char.trim().isEmpty) continue;
      if (g.bounds.width > width * 0.5) {
        continue; // Exclude wide spanner from gutter detection
      }
      final bStart = (((g.bounds.left - minX) / width) * bucketCount)
          .floor()
          .clamp(0, bucketCount - 1);
      final bEnd = (((g.bounds.right - minX) / width) * bucketCount)
          .floor()
          .clamp(0, bucketCount - 1);
      for (var b = bStart; b <= bEnd; b++) {
        buckets[b]++;
      }
    }

    // Look for a gutter in the central 30%..70% of the page
    final startCheck = (bucketCount * 0.30).floor();
    final endCheck = (bucketCount * 0.70).floor();

    var bestGutterCenter = -1;
    var minDensity = 999999;

    for (var i = startCheck; i <= endCheck; i++) {
      if (buckets[i] < minDensity) {
        minDensity = buckets[i];
        bestGutterCenter = i;
      }
    }

    // If there is a clear empty or nearly-empty gutter
    final leftMax = buckets.sublist(0, startCheck).reduce(math.max);
    final rightMax = buckets.sublist(endCheck).reduce(math.max);

    if (bestGutterCenter != -1 &&
        minDensity <= (math.min(leftMax, rightMax) * 0.20) &&
        leftMax >= 1 &&
        rightMax >= 1) {
      final splitX = minX + (bestGutterCenter / bucketCount) * width;
      final leftCol = <PdfGlyph>[];
      final rightCol = <PdfGlyph>[];
      final fullWidthSpanners = <PdfGlyph>[];

      for (final g in glyphs) {
        if (g.bounds.left < splitX &&
            g.bounds.right > splitX &&
            g.bounds.width > width * 0.6) {
          fullWidthSpanners.add(g);
        } else if (g.bounds.left < splitX) {
          leftCol.add(g);
        } else {
          rightCol.add(g);
        }
      }

      if (leftCol.isNotEmpty && rightCol.isNotEmpty) {
        if (fullWidthSpanners.isEmpty) {
          return [leftCol, rightCol];
        } else {
          // If there are top headings spanning full width, place them before columns
          final topSpanners = fullWidthSpanners
              .where(
                (g) =>
                    g.bounds.top <
                    math.min(
                      leftCol.first.bounds.top,
                      rightCol.first.bounds.top,
                    ),
              )
              .toList();
          final remainderSpanners = fullWidthSpanners
              .where((g) => !topSpanners.contains(g))
              .toList();

          final result = <List<PdfGlyph>>[];
          if (topSpanners.isNotEmpty) result.add(topSpanners);
          result.add(leftCol);
          result.add(rightCol);
          if (remainderSpanners.isNotEmpty) result.add(remainderSpanners);
          return result;
        }
      }
    }

    return [glyphs];
  }

  List<PdfLine> _assembleColumnLines(List<PdfGlyph> glyphs, int pageNumber) {
    if (glyphs.isEmpty) return const [];

    // Sort by approximate vertical position
    final sorted = List<PdfGlyph>.from(glyphs)
      ..sort((a, b) {
        final cmpY = a.bounds.top.compareTo(b.bounds.top);
        if (cmpY != 0) return cmpY;
        return a.bounds.left.compareTo(b.bounds.left);
      });

    final lineClusters = <List<PdfGlyph>>[];
    for (final glyph in sorted) {
      var added = false;
      for (final cluster in lineClusters) {
        final clusterY = cluster.first.bounds.top;
        final clusterHeight = cluster.first.effectiveFontHeight;
        final tolerance = clusterHeight * 0.45;

        if ((glyph.bounds.top - clusterY).abs() <= tolerance) {
          cluster.add(glyph);
          added = true;
          break;
        }
      }
      if (!added) {
        lineClusters.add([glyph]);
      }
    }

    // Sort clusters from top to bottom
    lineClusters.sort(
      (a, b) => a.first.bounds.top.compareTo(b.first.bounds.top),
    );

    final lines = <PdfLine>[];
    for (final cluster in lineClusters) {
      cluster.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));

      final sb = StringBuffer();
      var minL = 1.0, minT = 1.0, maxR = 0.0, maxB = 0.0;
      var totalH = 0.0;
      var hasSup = false;

      final medianH = _computeMedianHeight(cluster);

      for (var i = 0; i < cluster.length; i++) {
        final g = cluster[i];
        if (i > 0) {
          final prev = cluster[i - 1];
          final gap = g.bounds.left - prev.bounds.right;
          // Insert space if there is a gap larger than 25% of character height and not already space
          if (gap > (prev.effectiveFontHeight * 0.25) &&
              !sb.toString().endsWith(' ') &&
              g.char != ' ') {
            sb.write(' ');
          }
        }
        sb.write(g.char);
        minL = math.min(minL, g.bounds.left);
        minT = math.min(minT, g.bounds.top);
        maxR = math.max(maxR, g.bounds.right);
        maxB = math.max(maxB, g.bounds.bottom);
        totalH += g.effectiveFontHeight;

        // Check superscript: significantly smaller and shifted upwards
        if (g.effectiveFontHeight < medianH * 0.8 &&
            g.bounds.bottom < (minT + medianH * 0.7)) {
          hasSup = true;
        }
      }

      final text = sb.toString().trim();
      if (text.isNotEmpty) {
        lines.add(
          PdfLine(
            text: text,
            bounds: PdfRectNormalized(
              left: minL,
              top: minT,
              width: math.max(0.0, maxR - minL),
              height: math.max(0.0, maxB - minT),
            ),
            pageNumber: pageNumber,
            fontHeight: totalH / cluster.length,
            hasSuperscript: hasSup,
          ),
        );
      }
    }

    return lines;
  }

  double _computeMedianHeight(List<PdfGlyph> glyphs) {
    if (glyphs.isEmpty) return 0.0;
    final heights = glyphs.map((g) => g.effectiveFontHeight).toList()..sort();
    return heights[heights.length ~/ 2];
  }

  /// Calculates the document body font size by weighted character mode.
  double computeBodyFontSize(List<PdfLine> lines) {
    if (lines.isEmpty) return 12.0;

    final histogram = <double, int>{};
    for (final l in lines) {
      final rounded = (l.fontHeight * 1000).round() / 1000;
      histogram[rounded] = (histogram[rounded] ?? 0) + l.text.length;
    }

    var bestSize = 12.0;
    var maxWeight = -1;
    for (final entry in histogram.entries) {
      if (entry.value > maxWeight) {
        maxWeight = entry.value;
        bestSize = entry.key;
      }
    }

    return bestSize;
  }

  /// Filters recurring headers/footers, page numbers, and footnotes.
  List<PdfLine> filterHeadersFootersAndFootnotes(
    List<PdfLine> allLines, {
    required int totalPages,
    required double bodyFontSize,
  }) {
    if (allLines.isEmpty) return const [];

    // Group lines by normalized content in header (< margin) and footer (> 1 - margin)
    final headerCandidates = <String, Set<int>>{};
    final footerCandidates = <String, Set<int>>{};

    for (final line in allLines) {
      final norm = _normalizeHeaderPattern(line.text);
      if (norm.isEmpty) continue;

      if (line.bounds.top <= headerFooterMarginRatio) {
        headerCandidates.putIfAbsent(norm, () => <int>{}).add(line.pageNumber);
      } else if (line.bounds.bottom >= (1.0 - headerFooterMarginRatio)) {
        footerCandidates.putIfAbsent(norm, () => <int>{}).add(line.pageNumber);
      }
    }

    final minFreqPages = math.max(
      2,
      (totalPages * headerFooterFrequencyThreshold).ceil(),
    );
    final dropHeaders = headerCandidates.entries
        .where((e) => e.value.length >= minFreqPages)
        .map((e) => e.key)
        .toSet();
    final dropFooters = footerCandidates.entries
        .where((e) => e.value.length >= minFreqPages)
        .map((e) => e.key)
        .toSet();

    final filtered = <PdfLine>[];
    for (final line in allLines) {
      final isHeaderZone = line.bounds.top <= headerFooterMarginRatio;
      final isFooterZone =
          line.bounds.bottom >= (1.0 - headerFooterMarginRatio);
      final norm = _normalizeHeaderPattern(line.text);

      // Check recurring header/footer
      if (isHeaderZone && dropHeaders.contains(norm)) continue;
      if (isFooterZone && dropFooters.contains(norm)) continue;

      // Check standalone page number
      if ((isHeaderZone || isFooterZone) &&
          _isStandalonePageNumber(line.text)) {
        continue;
      }

      // Check footnote: bottom area, font size < 0.85x body, starts with digit or asterisk
      if (isFooterZone &&
          line.fontHeight <= (bodyFontSize * footnoteFontScale) &&
          _isFootnoteLeader(line.text)) {
        continue;
      }

      filtered.add(line);
    }

    return filtered;
  }

  static String _normalizeHeaderPattern(String text) {
    // Strip numbers, punctuation, roman numerals to match running book/chapter titles
    return text
        .replaceAll(RegExp(r'[\d\s\-_–—\.\,\:\;\|\/\\•]+'), ' ')
        .trim()
        .toLowerCase();
  }

  static bool _isStandalonePageNumber(String text) {
    final t = text.trim();
    // Arabic numerals: "12", "- 12 -", "[12]", "Page 12"
    if (RegExp(
      r'^[-–—\s\[\(]*(?:page\s+)?\d+[-–—\s\]\)]*$',
      caseSensitive: false,
    ).hasMatch(t)) {
      return true;
    }
    // Roman numerals: "xii", "IV", "- iv -"
    if (RegExp(
      r'^[-–—\s\[\(]*[ivxlcdm]+[-–—\s\]\)]*$',
      caseSensitive: false,
    ).hasMatch(t)) {
      return true;
    }
    return false;
  }

  static bool _isFootnoteLeader(String text) {
    final t = text.trim();
    return RegExp(r'^(\d+[\.\)\s]|\*|\†|\‡)').hasMatch(t);
  }

  /// Transforms filtered lines into structured paragraphs, headings, and scene breaks.
  List<PdfLocatedBlock> processToBlocks(
    List<PdfLine> lines, {
    required double bodyFontSize,
  }) {
    if (lines.isEmpty) return const [];

    final blocks = <PdfLocatedBlock>[];

    var currentLines = <PdfLine>[];
    ParagraphType currentType = ParagraphType.paragraph;

    void flushCurrent() {
      if (currentLines.isEmpty) return;

      final joined = _joinLinesToParagraph(currentLines);
      if (joined.isNotEmpty) {
        final first = currentLines.first;
        final last = currentLines.last;
        final minL = currentLines.map((l) => l.bounds.left).reduce(math.min);
        final minT = first.bounds.top;
        final maxR = currentLines.map((l) => l.bounds.right).reduce(math.max);
        final maxB = last.bounds.bottom;

        blocks.add(
          PdfLocatedBlock(
            type: currentType,
            text: joined,
            pageNumber: first.pageNumber,
            bounds: PdfRectNormalized(
              left: minL,
              top: minT,
              width: math.max(0.0, maxR - minL),
              height: math.max(0.0, maxB - minT),
            ),
          ),
        );
      }

      currentLines = [];
      currentType = ParagraphType.paragraph;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 1. Scene break detection: "***", "* * *", "---", "###"
      if (_isSceneBreak(line.text)) {
        flushCurrent();
        blocks.add(
          PdfLocatedBlock(
            type: ParagraphType.sceneBreak,
            text: '***',
            pageNumber: line.pageNumber,
            bounds: line.bounds,
          ),
        );
        continue;
      }

      // 2. Drop cap handling: single large letter preceding text
      if (_isDropCap(line, lines, i, bodyFontSize)) {
        // Merge drop cap letter with next line
        final nextLine = lines[i + 1];
        final mergedLine = PdfLine(
          text: '${line.text}${nextLine.text}',
          bounds: PdfRectNormalized(
            left: math.min(line.bounds.left, nextLine.bounds.left),
            top: math.min(line.bounds.top, nextLine.bounds.top),
            width:
                math.max(line.bounds.right, nextLine.bounds.right) -
                math.min(line.bounds.left, nextLine.bounds.left),
            height:
                math.max(line.bounds.bottom, nextLine.bounds.bottom) -
                math.min(line.bounds.top, nextLine.bounds.top),
          ),
          pageNumber: line.pageNumber,
          fontHeight: nextLine.fontHeight,
          hasSuperscript: nextLine.hasSuperscript,
        );
        lines[i + 1] = mergedLine;
        continue;
      }

      // 3. Heading detection: font scale >= 1.2x body or pattern (Chapter N, Bab N, Part)
      final isHeading = _isHeadingLine(line, bodyFontSize);

      if (isHeading) {
        flushCurrent();
        currentType = ParagraphType.heading;
        currentLines.add(line);
        flushCurrent();
        continue;
      }

      // 4. Paragraph boundary check against previous line in currentLines
      if (currentLines.isNotEmpty) {
        final prev = currentLines.last;
        final isNewPara = _isParagraphBoundary(prev, line, bodyFontSize);

        if (isNewPara) {
          flushCurrent();
        }
      }

      currentLines.add(line);
    }

    flushCurrent();

    // 5. Connect hyphenated words and cross-page paragraphs
    return _postProcessBlocks(blocks);
  }

  static bool _isSceneBreak(String text) {
    final t = text.trim();
    if (t == '***' ||
        t == '* * *' ||
        t == '---' ||
        t == '- - -' ||
        t == '___' ||
        t == '• • •' ||
        t == '###') {
      return true;
    }
    return false;
  }

  bool _isHeadingLine(PdfLine line, double bodyFontSize) {
    final t = line.text.trim();
    if (line.fontHeight >= (bodyFontSize * headingFontScale)) {
      return true;
    }
    // Pattern: Chapter N, Bab N, Part N, Act N, Scene N
    if (RegExp(
      r'^(?:chapter|bab|part|bagian|act|scene)\s+(?:\d+|[ivxlcdm]+)',
      caseSensitive: false,
    ).hasMatch(t)) {
      return true;
    }
    return false;
  }

  bool _isDropCap(
    PdfLine line,
    List<PdfLine> lines,
    int index,
    double bodyFontSize,
  ) {
    if (line.text.trim().length == 1 &&
        line.fontHeight >= (bodyFontSize * 1.5) &&
        index + 1 < lines.length) {
      final next = lines[index + 1];
      if (next.pageNumber == line.pageNumber &&
          (next.bounds.top - line.bounds.top).abs() < (line.fontHeight * 0.8)) {
        return true;
      }
    }
    return false;
  }

  bool _isParagraphBoundary(PdfLine prev, PdfLine curr, double bodyFontSize) {
    // Different page
    if (curr.pageNumber != prev.pageNumber) {
      // Connect across pages if prev does not end with terminal punctuation
      // and curr starts with a lowercase letter
      if (!_hasTerminalPunctuation(prev.text.trim()) &&
          RegExp(r'^[a-z]').hasMatch(curr.text.trim())) {
        return false;
      }
      return true;
    }

    // Significant vertical gap (> 1.5x normal spacing)
    final lineSpacing = curr.bounds.top - prev.bounds.bottom;
    if (lineSpacing > (bodyFontSize * paragraphGapScale * 0.05)) {
      return true;
    }

    // Indented first line
    if (curr.bounds.left > (prev.bounds.left + bodyFontSize * 0.03)) {
      return true;
    }

    // Previous line is short (< 80% column/line width) and ends with punctuation
    if (prev.text.trim().endsWith('.') ||
        prev.text.trim().endsWith('?') ||
        prev.text.trim().endsWith('!') ||
        prev.text.trim().endsWith('”') ||
        prev.text.trim().endsWith('"')) {
      if (prev.bounds.width < (curr.bounds.width * 0.82)) {
        return true;
      }
    }

    return false;
  }

  static String _joinLinesToParagraph(List<PdfLine> lines) {
    if (lines.isEmpty) return '';

    final sb = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      var t = lines[i].text.trim();

      // Remove superscript digits if marked
      if (lines[i].hasSuperscript) {
        t = t.replaceAll(RegExp(r'[\u00B2\u00B3\u00B9\u2070-\u207F]'), '');
      }

      if (i > 0) {
        final prev = sb.toString();
        // Check hyphenation: if prev ends with '-', and current starts with lowercase
        if (prev.endsWith('-') && RegExp(r'^[a-z]').hasMatch(t)) {
          final stripped = prev.substring(0, prev.length - 1);
          sb.clear();
          sb.write(stripped);
          sb.write(t);
          continue;
        } else {
          sb.write(' ');
        }
      }

      sb.write(t);
    }

    return sb.toString().trim();
  }

  static List<PdfLocatedBlock> _postProcessBlocks(
    List<PdfLocatedBlock> blocks,
  ) {
    if (blocks.length <= 1) return blocks;

    final out = <PdfLocatedBlock>[];
    var i = 0;

    while (i < blocks.length) {
      final current = blocks[i];

      // Cross-page paragraph join check
      if (i + 1 < blocks.length &&
          current.type == ParagraphType.paragraph &&
          blocks[i + 1].type == ParagraphType.paragraph) {
        final next = blocks[i + 1];

        // If current paragraph doesn't end with terminal punctuation
        // and next starts with lowercase letter or hyphen continuation
        if (!_hasTerminalPunctuation(current.text.trim()) &&
            (RegExp(r'^[a-z]').hasMatch(next.text.trim()) ||
                current.text.endsWith('-'))) {
          String mergedText;
          if (current.text.endsWith('-') &&
              RegExp(r'^[a-z]').hasMatch(next.text.trim())) {
            mergedText =
                '${current.text.substring(0, current.text.length - 1)}${next.text}';
          } else {
            mergedText = '${current.text} ${next.text}';
          }

          out.add(
            PdfLocatedBlock(
              type: ParagraphType.paragraph,
              text: mergedText,
              pageNumber: current.pageNumber,
              bounds: current.bounds,
            ),
          );
          i += 2;
          continue;
        }
      }

      out.add(current);
      i++;
    }

    return out;
  }
}
