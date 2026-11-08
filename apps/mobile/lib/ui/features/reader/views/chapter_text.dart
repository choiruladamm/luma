import 'package:luma/l10n/l10n.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Isi satu bab: scroll, tap paragraf, restore posisi, highlight grup Artinya
/// dan hasil Cari kata. API publik state-nya dipanggil [ReaderView] lewat key.
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

  /// Titik yang langsung dituju pas kebuka (posisi tersimpan).
  final Spot? restoreTo;

  /// Titik paling atas yang keliatan, tiap user selesai scroll.
  final ValueChanged<Spot> onPosition;

  /// Tap paragraf → sheet Artinya.
  final ValueChanged<ReaderParagraph> onParagraphTap;

  /// Grup yang lagi dibuka di sheet Artinya: distabilo, scrim dibolongin di
  /// situ.
  final int? openGroup;
  final ChatSource? sourceVisit;
  final VoidCallback onNext;

  /// Mode Cari kata: kata cocok di-stabilo di semua paragraf bab ini.
  final SearchMarks? search;

  /// Lagi mode cari: kedatangan di [restoreTo] = lompat dari hasil (kedip
  /// paragraf), bukan "Lanjut baca".
  final bool flashSearch;

  /// Scroll jari mulai (true) / berhenti (false).
  final ValueChanged<bool>? onScrollActive;

  /// User udah scroll 1 layar dari paragraf hasil.
  final VoidCallback? onSearchRead;

  @override
  ConsumerState<ChapterText> createState() => ChapterTextState();
}

class ChapterTextState extends ConsumerState<ChapterText> {
  final _scroll = ScrollController();
  final _contentKey = GlobalKey();
  final _markKey = GlobalKey<ReadMarkState>();
  Timer? _introTimer;

  /// Satu key per paragraf (indeks paragraf di DB) buat ngukur & lompat.
  // ponytail: satu chapter dirender utuh (Column), bukan lazy. Aman buat
  // chapter ratusan paragraf; ganti ke list yang bisa lompat ke item kalau
  // ada buku dengan chapter raksasa yang kerasa berat.
  final _keys = <int, GlobalKey>{};
  bool _restored = false;

  /// Scroll dari jari (bukan lompatan restore) yang belum dilaporin.
  bool _userScrolled = false;

  /// Posisi scroll waktu lompat dari hasil cari; null = gak lagi nunggu.
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

  /// Paragraf paling atas yang keliatan di bawah safe area atas, plus bagian
  /// paragraf itu yang udah lewat garis tersebut.
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
    // Udah lewat semua paragraf (kartu akhir bab): akhir paragraf terakhir.
    return (index: paras.last.index, offset: 1);
  }

  /// Kapsul ngikutin scroll dari jari. Awal bab (80pt pertama) & akhir bab
  /// (paragraf terakhir keliatan) kapsulnya muncul sendiri.
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

  /// Tap paragraf → Artinya; selain itu (margin, sela, bawah teks terakhir,
  /// heading) → munculin/ngumpetin kapsul. Kotak paragraf selebar kolom,
  /// tapi area tap margin minimal [_minTapMargin]: di margin Sempit (16),
  /// 8pt pinggir kolom ikut diitung kosong.
  void _onTap(Offset point, List<ReaderParagraph> paras) {
    _introTimer?.cancel(); // udah pegang kendali sendiri
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

  /// Paragraf terakhir yang dirender, buat ngukur posisi pas setelan Aa
  /// diganti (layout lama masih ada di [didUpdateWidget]).
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
    // Tinggi paragraf berubah: titik yang lagi di garis atas tetep di situ.
    final spot = _topSpot(_paras);
    if (spot == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _place(spot, MediaQuery.paddingOf(context).top);
      _track();
    });
  }

  /// Geser scroll sampe [spot] ada di [y] (global). Mentok di ujung scroll.
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

  /// Taruh titik tersimpan di ±⅓ tinggi layar, biar ada konteks di atasnya.
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
    // Baru keliatan setelah di posisi yang bener (lihat AnimatedOpacity).
    setState(() => _restored = true);
  }

  /// Kotak paragraf-paragraf satu grup, di koordinat [ancestor] (null =
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

  /// Blok stabilo grup: melebar setengah margin ke samping, 8pt atas-bawah.
  Rect _highlight(Rect group) {
    final side = widget.prefs.marginWidth / 2;
    return Rect.fromLTRB(
      group.left - side,
      group.top - Space.s2,
      group.right + side,
      group.bottom + Space.s2,
    );
  }

  /// Grup sesudah [group] di bab ini, null kalau udah yang terakhir.
  int? groupAfter(int group) => _paras
      .map((p) => p.groupIndex)
      .whereType<int>()
      .where((g) => g > group)
      .firstOrNull;

  double get pixels => _scroll.hasClients ? _scroll.offset : 0;

  /// Sheet Artinya: halaman ikut naik barengan sheet sampe bawah blok grup =
  /// atas sheet − 16. Grup kepanjangan: atas bloknya = safe area + 16.
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

  /// Sheet Artinya baru dibuka: atas blok grup = safe area, selalu. Grup
  /// rata-rata lebih tinggi dari ruang di atas sheet, jadi bawahnya ketutup
  /// sheet (sama kayak cabang grup kepanjangan di [showGroupAbove]).
  Future<void> showGroupAtTop(int group) async {
    final r = _groupRect(group);
    if (r == null || !_scroll.hasClients) return;
    final delta = _highlight(r).top - MediaQuery.paddingOf(context).top;
    await _animateTo(pixels + delta, Motion.rise(delta), Motion.riseCurve);
  }

  final _pinCard = GlobalKey<MeaningPinCardState>();

  /// Card tetap buat grup kepanjangan (lihat [MeaningPinCard]): dipasang
  /// cuma kalau teks grupnya ketutup sheet.
  void pinGroup(int group, double sheetTop) {
    // Sheet bisa udah ditutup pas halaman masih naik.
    if (!mounted || widget.openGroup != group) return;
    final area = context.findRenderObject();
    final r = _groupRect(group, area);
    final paras = _paras.where((p) => p.groupIndex == group).toList();
    if (area is! RenderBox || r == null || paras.isEmpty) return;
    final block = _highlight(r);
    final sheetLocal = sheetTop - area.localToGlobal(Offset.zero).dy;
    // Teks (tanpa padding bawah blok) muat di atas sheet: gak ada yang di-scroll.
    if (block.bottom - Space.s2 <= sheetLocal - Layout.followGap) return;
    // Kartu terus ke bawah sheet; yang kelihatan cuma sampe atas sheet.
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

  /// Balik ke posisi sebelum sheet dibuka.
  Future<void> scrollBack(double to) =>
      _animateTo(to, Motion.sheetClose, Motion.sheetCloseCurve);

  Future<void> _animateTo(double to, Duration d, Curve curve) {
    final p = _scroll.position;
    final target = to.clamp(p.minScrollExtent, p.maxScrollExtent);
    if ((target - p.pixels).abs() < 0.5) return Future.value();
    // Kurangi gerakan: langsung pindah (animateTo gak mau durasi nol).
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
      return Future.value();
    }
    return _scroll.animateTo(target, duration: d, curve: curve);
  }

  /// Simpen titik yang sekarang di atas (abis halaman digeser sheet).
  void stopAndReportPosition() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
    reportPosition();
  }

  void reportPosition() {
    final spot = _topSpot(_paras);
    if (spot != null) widget.onPosition(spot);
  }

  /// Blok grup yang perlu digambar (dibuka + penanda udah diterjemahin), di
  /// koordinat isi bab. Diukur abis layout.
  Map<int, Rect> _groupRects = const {};

  /// Grup yang dibolongin di scrim Artinya.
  int? _scrimGroup;

  void _measureGroups(Set<int> groups) {
    final content = _contentKey.currentContext?.findRenderObject();
    if (content is! RenderBox) return;
    final rects = {for (final g in groups) g: ?_groupRect(g, content)};
    if (!mapEquals(rects, _groupRects)) setState(() => _groupRects = rects);
  }

  /// Abis lanjut baca: kapsul muncul bentar buat orientasi terus ngumpet,
  /// grup tersimpan dikasih kilatan sekali (Kurangi gerakan: garis kiri 4pt).
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

  /// Kedip muted di paragraf hasil cari ([Motion.searchFlash]); Kurangi
  /// gerakan: garis kiri 4pt kayak "Lanjut baca".
  void flashParagraph(int index) {
    final content = _contentKey.currentContext?.findRenderObject();
    final box = _box(index);
    if (box == null || content is! RenderBox) return;
    final r = box.localToGlobal(Offset.zero, ancestor: content) & box.size;
    _markKey.currentState?.show(r, Motion.searchFlash);
  }

  /// Lompat dari hasil cari (bab ini): paragraf ke ±⅓ tinggi layar, kedip.
  /// Paragraf gak ada (mis. judul bab yang gak dirender dobel) = ke awal bab.
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
    final gap = reading.fontSize!; // 1em antar paragraf
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
    // Inget grup terakhir biar bolongnya gak ilang pas scrim lagi fade out.
    if (open != null) _scrimGroup = open;

    if (loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        // Lompat ke posisi tersimpan sekali; chapter pendek yang gak perlu
        // di-scroll langsung dianggap kebaca.
        _restored ? _track() : _restore(paras);
      });
    }

    // Isi disembunyiin sampe teksnya kebaca & udah lompat ke posisi
    // tersimpan, terus fade in. Tanpa ini keliatan kedip: mulai dari atas,
    // lompat ke tengah, kartu akhir bab nongol duluan.
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
              // Tepi teks ikut varian kapsul ↔ imersif sepanjang animasi kapsul.
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
                    _introTimer?.cancel(); // udah pegang kendali sendiri
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
                // Tap area kosong (margin, sela, bawah teks terakhir) = munculin /
                // ngumpetin kapsul. Paragraf nangkep tap-nya sendiri.
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
                      // Penanda grup nongol di margin kiri, di luar kolom teks.
                      clipBehavior: Clip.none,
                      children: [
                        // Penanda grup yang udah diterjemahin: garis 4pt warna mark
                        // di tengah margin kiri, sepanjang grupnya.
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
                                // Key di isinya, bukan di sela bawah: offset = fraksi tinggi
                                // paragraf doang.
                                child: KeyedSubtree(
                                  key: _keys.putIfAbsent(
                                    p.index,
                                    GlobalKey.new,
                                  ),
                                  child: switch (p.type) {
                                    // Kotak paragraf selebar kolom, termasuk sisa baris
                                    // pendek. Sela antar paragraf & margin = area kosong.
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
                            // Kartu akhir bab baru muncul bareng teks, biar gak nongol di atas
                            // terus kedorong ke bawah.
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
        // Sheet Artinya: scrim nutup halaman kecuali blok grup yang dibuka
        // (grupnya kebaca di atas scrim). Ikut gerak pas halaman di-scroll.
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
        // Card kuning tetap (halaman gak geser): isinya yang di-scroll.
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

  /// Heading pertama yang isinya sama kayak judul chapter udah ditampilin di
  /// [ChapterHeading], gak usah dobel.
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
