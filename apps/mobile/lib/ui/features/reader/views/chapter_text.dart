import 'package:luma/l10n/l10n.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma/ui/features/reader/views/reader_view.dart' show ReaderView;

import '../../../../domain/models/book.dart';
import '../../../../domain/models/book_chat.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../../domain/reading.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/edge_fade.dart';
import '../view_models/reader_view_model.dart';
import 'reader_capsule.dart';
import 'chapter_end.dart';
import 'meaning_pin_card.dart';
import 'paragraph_text.dart';
import 'read_mark.dart';
import 'chapter_heading.dart';
import 'reader_types.dart';
import 'scrim_hole.dart';

/// Body of one chapter: scrolling, paragraph taps, position restore, highlights for the
/// Artinya group and Cari kata results. [ReaderView] calls its public state API through a key.
class ChapterText extends ConsumerStatefulWidget {
  const ChapterText({
    super.key,
    required this.book,
    required this.index,
    required this.fraction,
    required this.chrome,
    required this.prefs,
    required this.restoreTo,
    required this.onPosition,
    required this.onParagraphTap,
    required this.onNext,
    this.openGroup,
    this.sourceVisit,
    this.search,
    this.flashSearch = false,
    this.onScrollActive,
    this.onSearchRead,
  });

  final ReaderBook book;
  final int index;
  final ValueNotifier<double> fraction;
  final ReaderChrome chrome;
  final ReaderPrefs prefs;

  /// The point to jump to when opened (saved position).
  final Spot? restoreTo;

  /// The top-most visible point, reported each time the user finishes scrolling.
  final ValueChanged<Spot> onPosition;

  /// Paragraph tap → Artinya sheet.
  final ValueChanged<ReaderParagraph> onParagraphTap;

  /// The group open in the Artinya sheet: highlighted, with a hole cut in the scrim
  /// there.
  final int? openGroup;
  final ChatSource? sourceVisit;
  final VoidCallback onNext;

  /// Cari kata mode: matching words are highlighted in every paragraph of this chapter.
  final SearchMarks? search;

  /// In search mode: arriving at [restoreTo] = a jump from a result (paragraph flash),
  /// not "Lanjut baca".
  final bool flashSearch;

  /// Finger scroll started (true) / stopped (false).
  final ValueChanged<bool>? onScrollActive;

  /// The user has scrolled one screen away from the result paragraph.
  final VoidCallback? onSearchRead;

  @override
  ConsumerState<ChapterText> createState() => ChapterTextState();
}

class ChapterTextState extends ConsumerState<ChapterText> {
  final _scroll = ScrollController();
  final _contentKey = GlobalKey();
  final _markKey = GlobalKey<ReadMarkState>();
  Timer? _introTimer;

  /// One key per paragraph (paragraph index in the DB) for measuring and jumping.
  // ponytail: one chapter is rendered whole (Column), not lazily. Fine for
  // chapters of hundreds of paragraphs; switch to a list that can jump to an item if
  // a book with a giant chapter feels heavy.
  final _keys = <int, GlobalKey>{};
  bool _restored = false;

  /// Finger scroll (not a restore jump) not yet reported.
  bool _userScrolled = false;

  /// Scroll position when jumping from a search result; null = not waiting.
  double? _searchAnchor;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_track);
  }

  void _track() {
    final p = _scroll.position;
    widget.fraction.value = p.maxScrollExtent <= 0
        ? 1
        : (p.pixels / p.maxScrollExtent).clamp(0, 1).toDouble();
  }

  RenderBox? _box(int index) {
    final box = _keys[index]?.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box : null;
  }

  /// The top-most paragraph visible below the top safe area, plus the part of that
  /// paragraph already past that line.
  Spot? _topSpot(List<ReaderParagraph> paras) {
    final area = context.findRenderObject() as RenderBox?;
    if (area == null || !area.hasSize || paras.isEmpty) return null;
    final line = math.max(
      area.localToGlobal(Offset.zero).dy,
      MediaQuery.paddingOf(context).top,
    );
    for (final p in paras) {
      final box = _box(p.index);
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final h = box.size.height;
      if (top + h > line + 0.5) {
        return (index: p.index, offset: ((line - top) / h).clamp(0.0, 1.0));
      }
    }
    // Past all paragraphs (chapter-end card): the end of the last paragraph.
    return (index: paras.last.index, offset: 1);
  }

  /// The capsules follow finger scrolling. At the chapter start (first 80pt) and end
  /// (last paragraph visible) the capsules appear on their own.
  void _moveChrome(ScrollUpdateNotification n, List<ReaderParagraph> paras) {
    final last = paras.isEmpty ? null : _box(paras.last.index);
    final atEnd =
        last != null &&
        last.localToGlobal(Offset.zero).dy < MediaQuery.sizeOf(context).height;
    if (n.metrics.pixels < _chapterStart || atEnd) {
      widget.chrome.show();
    } else {
      widget.chrome.scrolled(
        n.scrollDelta ?? 0,
        dragging: n.dragDetails != null,
      );
    }
  }

  static const _chapterStart = 80.0;

  /// Paragraph tap → Artinya; anything else (margin, gap, below the last text,
  /// heading) → shows/hides the capsules. The paragraph box is as wide as the column,
  /// but the margin tap area is at least [_minTapMargin]: with the "Sempit" margin (16),
  /// 8pt at the column edge counts as empty.
  void _onTap(Offset point, List<ReaderParagraph> paras) {
    _introTimer?.cancel(); // the finger has taken over
    final edge = math.max(0.0, _minTapMargin - widget.prefs.marginWidth);
    for (final p in paras) {
      if (p.type != ParagraphType.paragraph) continue;
      final box = _box(p.index);
      if (box == null) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (Rect.fromLTRB(
        r.left + edge,
        r.top,
        r.right - edge,
        r.bottom,
      ).contains(point)) {
        widget.onParagraphTap(p);
        return;
      }
    }
    widget.chrome.toggle();
  }

  static const _minTapMargin = 24.0;

  ReaderParagraph? get lastParagraph => _paras.lastOrNull;

  /// The last rendered paragraph, to measure the position when the Aa settings change
  /// (the old layout still exists in [didUpdateWidget]).
  List<ReaderParagraph> _paras = const [];

  @override
  void didUpdateWidget(ChapterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final p = widget.prefs;
    final changed =
        p.fontSize != oldWidget.prefs.fontSize ||
        p.font != oldWidget.prefs.font ||
        p.lineHeight != oldWidget.prefs.lineHeight ||
        p.marginWidth != oldWidget.prefs.marginWidth;
    if (!changed || !_restored) return;
    // Paragraph heights changed: the point at the top line stays there.
    final spot = _topSpot(_paras);
    if (spot == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _place(spot, MediaQuery.paddingOf(context).top);
      _track();
    });
  }

  /// Scrolls until [spot] is at [y] (global). Stops at the scroll extent.
  bool _place(Spot spot, double y) {
    final box = _box(spot.index);
    if (box == null || !_scroll.hasClients) return false;
    final p = _scroll.position;
    final point =
        box.localToGlobal(Offset.zero).dy + spot.offset * box.size.height;
    _scroll.jumpTo(
      (p.pixels + point - y).clamp(p.minScrollExtent, p.maxScrollExtent),
    );
    return true;
  }

  /// Places the saved point at about ⅓ of the screen height, leaving context above it.
  void _restore(List<ReaderParagraph> paras) {
    final spot = widget.restoreTo;
    if (spot != null) {
      final source = widget.sourceVisit;
      var target = spot;
      var y = MediaQuery.sizeOf(context).height / 3;
      if (source != null) {
        final anchor = source.anchors.first;
        final box = _box(spot.index);
        if (box is RenderParagraph && box.size.height > 0) {
          final rects = box.getBoxesForSelection(
            TextSelection(baseOffset: anchor.start, extentOffset: anchor.end),
          );
          if (rects.isNotEmpty) {
            target = (
              index: spot.index,
              offset: rects.first.top / box.size.height,
            );
            if (rects.last.bottom - rects.first.top >
                MediaQuery.sizeOf(context).height / 2) {
              y = MediaQuery.paddingOf(context).top + Layout.touch + Space.s5;
            }
          }
        }
      }
      if (_place(target, y) && source == null) {
        if (widget.flashSearch) {
          flashParagraph(spot.index);
          _searchAnchor = _scroll.offset;
        } else {
          _greet(paras, spot);
        }
      }
    }
    if (_scroll.hasClients) _track();
    // Only visible once at the right position (see AnimatedOpacity).
    setState(() => _restored = true);
  }

  /// Boxes of the paragraphs of one group, in [ancestor] coordinates (null =
  /// global).
  Rect? _groupRect(int group, [RenderObject? ancestor]) {
    Rect? rect;
    for (final p in _paras.where((p) => p.groupIndex == group)) {
      final box = _box(p.index);
      if (box == null) continue;
      final r = box.localToGlobal(Offset.zero, ancestor: ancestor) & box.size;
      rect = rect?.expandToInclude(r) ?? r;
    }
    return rect;
  }

  /// Highlight block of a group: extends half a margin sideways, 8pt above and below.
  Rect _highlight(Rect group) {
    final side = widget.prefs.marginWidth / 2;
    return Rect.fromLTRB(
      group.left - side,
      group.top - Space.s2,
      group.right + side,
      group.bottom + Space.s2,
    );
  }

  /// The group after [group] in this chapter, null when it is the last.
  int? groupAfter(int group) => _paras
      .map((p) => p.groupIndex)
      .whereType<int>()
      .where((g) => g > group)
      .firstOrNull;

  double get pixels => _scroll.hasClients ? _scroll.offset : 0;

  /// Artinya sheet: the page rises together with the sheet until the bottom of the
  /// group block = sheet top − 16. A too-long group: the block top = safe area + 16.
  Future<void> showGroupAbove(int group, double sheetTop) async {
    final r = _groupRect(group);
    if (r == null || !_scroll.hasClients) return;
    final block = _highlight(r);
    final top = MediaQuery.paddingOf(context).top + Space.s4;
    final bottom = sheetTop - Space.s4;
    final delta = block.height <= bottom - top
        ? block.bottom - bottom
        : block.top - top;
    await _animateTo(pixels + delta, Motion.sheetOpen, Motion.sheetOpenCurve);
  }

  /// Artinya sheet just opened: the group block top = safe area, always. The average
  /// group is taller than the space above the sheet, so its bottom is covered by the
  /// sheet (same as the too-long branch in [showGroupAbove]).
  Future<void> showGroupAtTop(int group) async {
    final r = _groupRect(group);
    if (r == null || !_scroll.hasClients) return;
    final delta = _highlight(r).top - MediaQuery.paddingOf(context).top;
    await _animateTo(pixels + delta, Motion.rise(delta), Motion.riseCurve);
  }

  final _pinCard = GlobalKey<MeaningPinCardState>();

  /// Fixed card for a too-long group (see [MeaningPinCard]): mounted only when the
  /// group text is covered by the sheet.
  void pinGroup(int group, double sheetTop) {
    // The sheet may already be closed while the page is still rising.
    if (!mounted || widget.openGroup != group) return;
    final area = context.findRenderObject();
    final r = _groupRect(group, area);
    final paras = _paras.where((p) => p.groupIndex == group).toList();
    if (area is! RenderBox || r == null || paras.isEmpty) return;
    final block = _highlight(r);
    final sheetLocal = sheetTop - area.localToGlobal(Offset.zero).dy;
    // The text (without the block bottom padding) fits above the sheet: nothing to scroll.
    if (block.bottom - Space.s2 <= sheetLocal - Layout.followGap) return;
    // The card continues below the sheet; only the part up to the sheet top is visible.
    _pinCard.currentState?.show(
      Rect.fromLTWH(
        block.left,
        block.top,
        block.width,
        math.max(0.0, sheetLocal - block.top),
      ),
      paras,
    );
  }

  Future<void> unpinGroup({bool animate = true}) =>
      _pinCard.currentState?.unpin(animate: animate) ?? Future.value();

  void followProgress(double progress, double sheetTop) =>
      _pinCard.currentState?.follow(progress, sheetTop);

  /// Returns to the position from before the sheet opened.
  Future<void> scrollBack(double to) =>
      _animateTo(to, Motion.sheetClose, Motion.sheetCloseCurve);

  Future<void> _animateTo(double to, Duration d, Curve curve) {
    final p = _scroll.position;
    final target = to.clamp(p.minScrollExtent, p.maxScrollExtent);
    if ((target - p.pixels).abs() < 0.5) return Future.value();
    // Reduce motion: jump directly (animateTo rejects a zero duration).
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
      return Future.value();
    }
    return _scroll.animateTo(target, duration: d, curve: curve);
  }

  /// Saves the point now at the top (after the sheet moved the page).
  void stopAndReportPosition() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
    reportPosition();
  }

  void reportPosition() {
    final spot = _topSpot(_paras);
    if (spot != null) widget.onPosition(spot);
  }

  /// Group blocks that need drawing (the open one + the translated markers), in
  /// chapter-body coordinates. Measured after layout.
  Map<int, Rect> _groupRects = const {};

  /// The group cut out of the Artinya scrim.
  int? _scrimGroup;

  void _measureGroups(Set<int> groups) {
    final content = _contentKey.currentContext?.findRenderObject();
    if (content is! RenderBox) return;
    final rects = {for (final g in groups) g: ?_groupRect(g, content)};
    if (!mapEquals(rects, _groupRects)) setState(() => _groupRects = rects);
  }

  /// After continuing reading: the capsules appear briefly for orientation then hide,
  /// and the saved group gets a one-time flash (Reduce motion: 4pt left line).
  void _greet(List<ReaderParagraph> paras, Spot spot) {
    widget.chrome.show();
    _introTimer = Timer(Motion.capsuleIntro, widget.chrome.hide);

    final group = paras
        .where((p) => p.index == spot.index)
        .firstOrNull
        ?.groupIndex;
    final content = _contentKey.currentContext?.findRenderObject();
    if (group == null || content is! RenderBox) return;
    final rect = _groupRect(group, content);
    if (rect == null) return;
    _markKey.currentState?.show(rect, Motion.flash);
  }

  /// Muted flash on the search result paragraph ([Motion.searchFlash]); Reduce
  /// motion: a 4pt left line like "Lanjut baca".
  void flashParagraph(int index) {
    final content = _contentKey.currentContext?.findRenderObject();
    final box = _box(index);
    if (box == null || content is! RenderBox) return;
    final r = box.localToGlobal(Offset.zero, ancestor: content) & box.size;
    _markKey.currentState?.show(r, Motion.searchFlash);
  }

  /// Jump from a search result (this chapter): paragraph to ~⅓ of the screen height,
  /// flash. Paragraph missing (e.g. a chapter title not rendered twice) = chapter start.
  void jumpToParagraph(int index) {
    if (!_scroll.hasClients) return;
    final placed = _place((
      index: index,
      offset: 0,
    ), MediaQuery.sizeOf(context).height / 3);
    if (!placed) _scroll.jumpTo(_scroll.position.minScrollExtent);
    _userScrolled = false;
    _track();
    _searchAnchor = _scroll.offset;
    flashParagraph(index);
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final chapter = widget.book.chapters[widget.index];
    final next = widget.index + 1 < widget.book.chapters.length
        ? widget.book.chapters[widget.index + 1]
        : null;
    final paragraphs = ref.watch(chapterParagraphsProvider(chapter.id));
    final reading = ReaderTypography(
      widget.prefs,
      Theme.of(context).brightness,
    ).style.copyWith(color: c.ink);
    final gap = reading.fontSize!; // 1em between paragraphs
    final pad = MediaQuery.paddingOf(context);
    final labelHeight = math.max(
      32.0,
      MediaQuery.textScalerOf(context).scale(12.5) * (18 / 13) + Space.s4,
    );
    final visitTop = math.max(Layout.chatHeader, 7 + labelHeight + Space.s2);
    final loaded = paragraphs is AsyncData;
    final paras = switch (paragraphs) {
      AsyncData(:final value) =>
        widget.sourceVisit == null
            ? _withoutTitleHeading(value, chapter.title)
            : value,
      _ => const <ReaderParagraph>[],
    };
    if (loaded && widget.sourceVisit != null) {
      try {
        for (final anchor in widget.sourceVisit!.anchors.where(
          (a) => a.chapterId == chapter.id,
        )) {
          final paragraph = paras
              .where((p) => p.index == anchor.paragraphIndex)
              .firstOrNull;
          if (paragraph == null) {
            throw FormatException(context.l10n.chapterSourceMissing);
          }
          anchor.validate((
            book: (
              bookId: widget.book.id,
              contentRevision: widget.book.contentRevision,
            ),
            chapterId: chapter.id,
            paragraphIndex: paragraph.index,
            text: paragraph.text,
          ), anchor.book);
        }
      } on FormatException {
        return Center(
          child: Text(context.l10n.readerThisSourceIsNoLongerAvailable),
        );
      }
    }
    _paras = paras;
    final translated =
        ref.watch(translatedGroupsProvider(chapter.id)).value ?? const {};
    final open = widget.openGroup;
    final drawn = {...translated, ?open};
    if (loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measureGroups(drawn);
      });
    }
    final onOpen = reading.copyWith(color: c.onHighlight);
    // Remember the last group so the hole does not vanish while the scrim fades out.
    if (open != null) _scrimGroup = open;

    if (loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        // Jump to the saved position once; a short chapter that needs no scrolling is
        // treated as read right away.
        _restored ? _track() : _restore(paras);
      });
    }

    // The body stays hidden until the text is readable and has jumped to the saved
    // position, then fades in. Without this you would see a flicker: starts at the top,
    // jumps to the middle, the chapter-end card appears first.
    final fade = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.contentFade;
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _restored ? 1 : 0,
            duration: fade,
            curve: Curves.easeOut,
            child: AnimatedBuilder(
              animation: widget.chrome.hidden,
              // The text edge follows the capsule ↔ immersive variant throughout the capsule animation.
              builder: (context, child) {
                final edges = readerEdgeFade(
                  pad,
                  widget.chrome.hidden.value,
                  bottomHeight: readerDockHeight(context),
                );
                return EdgeFadeScroll(
                  top: widget.sourceVisit == null
                      ? edges.top
                      : EdgeFadeSide(
                          Space.s5,
                          clear: pad.top + visitTop - Space.s5,
                        ),
                  bottom: widget.sourceVisit == null
                      ? edges.bottom
                      : EdgeFadeSide(
                          Space.s5,
                          clear: pad.bottom + Layout.chatHeader + Space.s3,
                        ),
                  child: child!,
                );
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is UserScrollNotification &&
                      n.direction != ScrollDirection.idle) {
                    _userScrolled = true;
                    _introTimer?.cancel(); // the finger has taken over
                    widget.onScrollActive?.call(true);
                  } else if (n is ScrollUpdateNotification &&
                      (_userScrolled || n.dragDetails != null)) {
                    _moveChrome(n, paras);
                  } else if (n is ScrollEndNotification && _userScrolled) {
                    _userScrolled = false;
                    widget.chrome.release();
                    widget.onScrollActive?.call(false);
                    final spot = _topSpot(paras);
                    if (spot != null) widget.onPosition(spot);
                    final anchor = _searchAnchor;
                    if (anchor != null &&
                        (_scroll.offset - anchor).abs() >=
                            MediaQuery.sizeOf(context).height) {
                      _searchAnchor = null;
                      widget.onSearchRead?.call();
                    }
                  }
                  return false;
                },
                // Tap on empty area (margin, gap, below the last text) = shows / hides the
                // capsules. A paragraph catches its own tap.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(d.globalPosition, paras),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      widget.prefs.marginWidth,
                      pad.top +
                          (widget.sourceVisit == null
                              ? readerTextTop
                              : visitTop),
                      widget.prefs.marginWidth,
                      pad.bottom +
                          readerTextBottom +
                          readerDockHeight(context) -
                          capsuleBottomHeight,
                    ),
                    child: Stack(
                      key: _contentKey,
                      // Group markers appear in the left margin, outside the text column.
                      clipBehavior: Clip.none,
                      children: [
                        // Marker of an already-translated group: a 4pt line in the mark color, in the
                        // middle of the left margin, along the group.
                        for (final g in translated)
                          if (g != open && _groupRects[g] != null)
                            Positioned(
                              key: ValueKey('mark-$g'),
                              left: -widget.prefs.marginWidth / 2 - 2,
                              top: _groupRects[g]!.top + 5,
                              height: math.max(0, _groupRects[g]!.height - 10),
                              width: 4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: c.mark,
                                  borderRadius: BorderRadius.circular(
                                    Radii.full,
                                  ),
                                ),
                              ),
                            ),
                        if (open != null && _groupRects[open] != null)
                          Positioned.fromRect(
                            rect: _highlight(_groupRects[open]!),
                            child: Semantics(
                              label: context
                                  .l10n
                                  .chapterCurrentlyOpenParagraphGroup,
                              child: DecoratedBox(
                                key: const ValueKey('open-group'),
                                decoration: BoxDecoration(
                                  color: c.highlight,
                                  borderRadius: BorderRadius.circular(Radii.md),
                                ),
                              ),
                            ),
                          ),
                        ReadMark(key: _markKey),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(bottom: gap),
                              child: ChapterHeading(
                                title: chapter.title,
                                number: widget.index + 1,
                                total: widget.book.chapters.length,
                                minutes: readingMinutes(chapter.chars),
                                reading: reading,
                              ),
                            ),
                            for (final p in paras)
                              Padding(
                                padding: EdgeInsets.only(bottom: gap),
                                // The key sits on the content, not the bottom gap: the offset is a fraction of the
                                // paragraph height only.
                                child: KeyedSubtree(
                                  key: _keys.putIfAbsent(
                                    p.index,
                                    GlobalKey.new,
                                  ),
                                  child: switch (p.type) {
                                    // Paragraph box as wide as the column, including the rest of a short line. The gaps
                                    // between paragraphs and the margins = empty area.
                                    ParagraphType.paragraph => _paragraphText(
                                      p,
                                      p.groupIndex == open && open != null
                                          ? onOpen
                                          : reading,
                                    ),
                                    ParagraphType.heading => Semantics(
                                      header: true,
                                      child: _paragraphText(
                                        p,
                                        StabiloType.titleSm.copyWith(
                                          color: c.ink,
                                        ),
                                      ),
                                    ),
                                    ParagraphType.sceneBreak => Center(
                                      child: Text(
                                        '* * *',
                                        semanticsLabel:
                                            context.l10n.chapterSceneBreak,
                                        style: StabiloType.label.copyWith(
                                          color: c.ink2,
                                        ),
                                      ),
                                    ),
                                  },
                                ),
                              ),
                            // The chapter-end card only appears together with the text, so it does not show
                            // up at the top and then get pushed down.
                            if (loaded)
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: ChapterEnd(
                                  chapterId: chapter.id,
                                  title: chapter.title,
                                  next: next,
                                  nextNumber: widget.index + 2,
                                  total: widget.book.chapters.length,
                                  onNext: widget.onNext,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Artinya sheet: the scrim covers the page except the open group block (the group
        // is readable above the scrim). Moves along when the page scrolls.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: open == null ? 0 : 1,
              duration: open == null ? Motion.sheetClose : Motion.sheetOpen,
              child: CustomPaint(
                painter: ScrimHole(
                  color: c.scrim,
                  repaint: _scroll,
                  hole: () {
                    final g = _scrimGroup;
                    if (g == null) return null;
                    final r = _groupRect(g, context.findRenderObject());
                    return r == null ? null : _highlight(r);
                  },
                ),
              ),
            ),
          ),
        ),
        // Fixed yellow card (the page does not move): its content is what scrolls.
        MeaningPinCard(
          key: _pinCard,
          marginWidth: widget.prefs.marginWidth,
          gap: gap,
          style: onOpen,
        ),
      ],
    );
  }

  Widget _paragraphText(ReaderParagraph paragraph, TextStyle style) =>
      buildParagraphText(
        paragraph: paragraph,
        style: style,
        colors: context.stabilo,
        chapterId: widget.book.chapters[widget.index].id,
        search: widget.search,
        sourceVisit: widget.sourceVisit,
      );

  /// The first heading whose content equals the chapter title is already shown in
  /// [ChapterHeading], so don't duplicate it.
  static List<ReaderParagraph> _withoutTitleHeading(
    List<ReaderParagraph> paras,
    String title,
  ) {
    String norm(String s) =>
        s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    final first = paras.firstOrNull;
    return first != null &&
            first.type == ParagraphType.heading &&
            norm(first.text) == norm(title)
        ? paras.sublist(1)
        : paras;
  }
}
