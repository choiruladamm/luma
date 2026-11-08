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
    this.baselineY,
    this.medianGlyphWidth,
  });

  final String text;
  final PdfRectNormalized bounds;
  final int pageNumber;
  final double fontHeight;
  final bool hasSuperscript;

  /// Measured baseline / glyph width; null when the producer has none.
  final double? baselineY, medianGlyphWidth;

  /// Baseline y. Glyph boxes are tight (descenders push [bounds] bottom down),
  /// so line spacing is measured baseline to baseline. Default: box bottom.
  double get baseline => baselineY ?? bounds.bottom;

  /// Median glyph width (≈ half an em): the unit for indents. Default: half
  /// the font height.
  double get charWidth => medianGlyphWidth ?? fontHeight * 0.5;

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

    // Stream-run mode: PDFium already cut its text into lines ('\n' glyphs
    // from the service). Real PDFs give *tight* glyph boxes (a period is tiny,
    // `h` is taller than `a`), so clustering by box top splits one printed line
    // into many; PDFium's own line breaks don't have that problem.
    final runMode = glyphs.any((g) => g.char == '\n');

    final lineClusters = <List<PdfGlyph>>[];
    if (runMode) {
      var run = <PdfGlyph>[];
      for (final g in glyphs) {
        if (g.char == '\n') {
          if (run.isNotEmpty) lineClusters.add(run);
          run = <PdfGlyph>[];
        } else {
          run.add(g);
        }
      }
      if (run.isNotEmpty) lineClusters.add(run);
      // Scrambled streams: still read top to bottom.
      lineClusters.sort((a, b) => _medianBottom(a).compareTo(_medianBottom(b)));
    } else {
      _clusterByTop(glyphs, lineClusters);
    }

    final lines = <PdfLine>[];
    for (var cluster in lineClusters) {
      if (!runMode) {
        cluster.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
      } else {
        cluster = _withoutFootnoteMarks(cluster);
        if (cluster.isEmpty) continue;
      }

      final sb = StringBuffer();
      var minL = 1.0, minT = 1.0, maxR = 0.0, maxB = 0.0;
      final medianH = _computeMedianHeight(cluster);
      final glyphWidth = _medianWidth(cluster);
      var hasSup = false;

      for (var i = 0; i < cluster.length; i++) {
        final g = cluster[i];
        if (i > 0 && runMode) {
          // PDFium joins runs of different font size without a space
          // ("THE FATE OF" + "British"): a gap this wide is a space.
          // Quotes/apostrophes have wide side bearings ("it’s"): exempt.
          final prev = cluster[i - 1];
          if (prev.char.trim().isNotEmpty &&
              g.char.trim().isNotEmpty &&
              !_quote.hasMatch(prev.char) &&
              !_quote.hasMatch(g.char) &&
              g.bounds.left - prev.bounds.right > _glueGap * glyphWidth) {
            sb.write(' ');
          }
        }
        if (i > 0 && !runMode) {
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
        if (g.char.trim().isEmpty) continue; // spaces carry no real box
        minL = math.min(minL, g.bounds.left);
        minT = math.min(minT, g.bounds.top);
        maxR = math.max(maxR, g.bounds.right);
        maxB = math.max(maxB, g.bounds.bottom);

        // Check superscript: significantly smaller and shifted upwards
        if (g.effectiveFontHeight < medianH * 0.8 &&
            g.bounds.bottom < (minT + medianH * 0.7)) {
          hasSup = true;
        }
      }

      final text = sb.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
      if (text.isNotEmpty && maxR > minL) {
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
            fontHeight: _fontHeight(cluster),
            hasSuperscript: hasSup,
            baselineY: _medianBottom(cluster),
            medianGlyphWidth: glyphWidth,
          ),
        );
      }
    }

    return lines;
  }

  /// A gap wider than this many median glyph widths (≈ 0.2 em) between two
  /// glyphs with no space glyph is a missing space.
  static const _glueGap = 0.55;
  static final _quote = RegExp(r'''[’'`‘“”"]''');

  /// Footnote / endnote reference digits ("Christ.1"): small digits raised
  /// above the baseline. They would end up glued to the word and in whatever
  /// gets translated, so they are removed from the line.
  static List<PdfGlyph> _withoutFootnoteMarks(List<PdfGlyph> cluster) {
    final f = _fontHeight(cluster);
    final base = _medianBottom(cluster);
    final isMark = [
      for (final g in cluster)
        // Raised off the baseline. (Size is no guide: in real books a
        // superscript digit's box is nearly as tall as an ascender.)
        _digit.hasMatch(g.char) && g.bounds.bottom < base - f * 0.25,
    ];
    if (!isMark.contains(true)) return cluster;
    final kept = [
      for (final (i, g) in cluster.indexed)
        if (!isMark[i]) g,
    ];
    // Nothing but marks on the line: leave it (a page number, a list index).
    return kept.any((g) => g.char.trim().isNotEmpty) ? kept : cluster;
  }

  static final _digit = RegExp(r'^[0-9]$');

  /// Font size proxy from *tight* boxes: the 80th percentile of letter/digit
  /// heights. The median swings with how many tall letters a line happens to
  /// have (so heading detection fired on ordinary lines); the upper
  /// percentile is the ascender/cap height, which every line has.
  static double _fontHeight(List<PdfGlyph> cluster) {
    final h = [
      for (final g in cluster)
        if (_isLetterOrDigit(g.char)) g.effectiveFontHeight,
    ]..sort();
    if (h.isEmpty) return _computeMedianHeight(cluster);
    return h[((h.length - 1) * 0.8).floor()];
  }

  static final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static bool _isLetterOrDigit(String c) => _letterOrDigit.hasMatch(c);

  static double _medianWidth(List<PdfGlyph> cluster) {
    final w = [
      for (final g in cluster)
        if (g.char.trim().isNotEmpty && g.bounds.width > 0) g.bounds.width,
    ]..sort();
    return w.isEmpty ? 0 : w[w.length ~/ 2];
  }

  static double _medianBottom(List<PdfGlyph> cluster) {
    final b = [
      for (final g in cluster)
        if (g.char.trim().isNotEmpty) g.bounds.bottom,
    ]..sort();
    return b.isEmpty ? 0 : b[b.length ~/ 2];
  }

  /// Fallback when PDFium gave no line breaks: 1-D clustering on glyph
  /// *bottoms* (the baseline; descenders and commas dip a little, tops vary
  /// with the letter), splitting where the next bottom is far from the last.
  void _clusterByTop(List<PdfGlyph> glyphs, List<List<PdfGlyph>> lineClusters) {
    final solid = [
      for (final g in glyphs)
        if (g.char.trim().isNotEmpty) g,
    ]..sort((a, b) => a.bounds.bottom.compareTo(b.bounds.bottom));
    if (solid.isEmpty) return;
    final gap = _computeMedianHeight(solid) * 0.7;
    var cluster = <PdfGlyph>[solid.first];
    for (final g in solid.skip(1)) {
      if (g.bounds.bottom - cluster.last.bounds.bottom > gap) {
        lineClusters.add(cluster);
        cluster = <PdfGlyph>[];
      }
      cluster.add(g);
    }
    lineClusters.add(cluster);
    lineClusters.sort((a, b) => _medianBottom(a).compareTo(_medianBottom(b)));
  }

  static double _computeMedianHeight(List<PdfGlyph> glyphs) {
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
    final stats = _FlowStats.of(lines);

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
        final isNewPara = _isParagraphBoundary(prev, line, bodyFontSize, stats);

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

  bool _isParagraphBoundary(
    PdfLine prev,
    PdfLine curr,
    double bodyFontSize,
    _FlowStats stats,
  ) {
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

    // Vertical gap bigger than the usual line pitch (baseline to baseline).
    if (stats.pitch > 0 &&
        curr.baseline - prev.baseline > stats.pitch * paragraphGapScale) {
      return true;
    }

    // Clear blank space between boxes (several glyph heights).
    if (curr.bounds.top - prev.bounds.bottom > curr.fontHeight * 3) {
      return true;
    }

    // Indented first line: starts clearly right of the previous line. Half an
    // em (≈ one median glyph width) is well above side-bearing noise.
    if (curr.bounds.left - prev.bounds.left > stats.charWidth * 1.0) {
      return true;
    }

    // Previous line stops short of the column and ends a sentence.
    final t = prev.text.trim();
    if (t.endsWith('.') ||
        t.endsWith('?') ||
        t.endsWith('!') ||
        t.endsWith('”') ||
        t.endsWith('"')) {
      if (prev.bounds.width < stats.columnWidth * 0.8) return true;
    }

    return false;
  }

  /// Words that are first halves of real compounds, so a line-end hyphen after
  /// them is kept ("two-" + "thirds"). Everything else is a soft hyphen.
  static final _compoundHead = RegExp(
    r'(?:^|[\s(“"])(?:one|two|three|four|five|six|seven|eight|nine|ten|'
    r'half|self|non|well|ill|long|short|high|low|full|multi|semi|ex|vice|'
    r'all|cross|old|new|first|second|third|fifth|tenth|twenty|thirty|forty|'
    r'fifty|state|world|user|real|part|full|open|so|e|x|co|re)-$',
    caseSensitive: false,
  );
  static bool _keepsHyphen(String prev) => _compoundHead.hasMatch(prev);

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
        if (prev.endsWith('-') &&
            RegExp(r'^[a-z]').hasMatch(t) &&
            !_keepsHyphen(prev)) {
          final stripped = prev.substring(0, prev.length - 1);
          sb.clear();
          sb.write(stripped);
          sb.write(t);
          continue;
        } else if (prev.endsWith('-') && RegExp(r'^[a-z]').hasMatch(t)) {
          // Real compound ("three-" + "character"): keep the hyphen, no space.
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
          blocks[i + 1].type == ParagraphType.paragraph &&
          // Only a page turn continues a paragraph; two blocks on the same
          // page were split on purpose (blank line, indent).
          blocks[i + 1].pageNumber > blocks[i].pageNumber) {
        final next = blocks[i + 1];

        // If current paragraph doesn't end with terminal punctuation
        // and next starts with lowercase letter or hyphen continuation
        if (!_hasTerminalPunctuation(current.text.trim()) &&
            (RegExp(r'^[a-z]').hasMatch(next.text.trim()) ||
                current.text.endsWith('-'))) {
          String mergedText;
          if (current.text.endsWith('-') &&
              RegExp(r'^[a-z]').hasMatch(next.text.trim())) {
            mergedText = _keepsHyphen(current.text)
                ? '${current.text}${next.text}'
                : '${current.text.substring(0, current.text.length - 1)}${next.text}';
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

/// Document-wide measures from the lines themselves, so thresholds follow the
/// real font and page instead of constants.
class _FlowStats {
  _FlowStats(this.pitch, this.charWidth, this.columnWidth);

  /// Median baseline-to-baseline distance of consecutive lines on a page.
  final double pitch;

  /// Median glyph width.
  final double charWidth;

  /// Typical full line width (90th percentile).
  final double columnWidth;

  factory _FlowStats.of(List<PdfLine> lines) {
    double median(List<double> v) {
      if (v.isEmpty) return 0;
      v.sort();
      return v[v.length ~/ 2];
    }

    final deltas = <double>[];
    for (var i = 1; i < lines.length; i++) {
      final d = lines[i].baseline - lines[i - 1].baseline;
      if (lines[i].pageNumber == lines[i - 1].pageNumber && d > 0) {
        deltas.add(d);
      }
    }
    final widths = [for (final l in lines) l.bounds.width]..sort();
    return _FlowStats(
      median(deltas),
      median([for (final l in lines) l.charWidth]),
      widths.isEmpty
          ? 0
          : widths[(widths.length * 0.9).floor().clamp(0, widths.length - 1)],
    );
  }
}
