import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/reading_progress_repository.dart';
import '../../../../routing/router.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/book.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../../domain/reading.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import '../view_models/reader_view_model.dart';
import 'aa_sheet.dart';
import 'book_end_view.dart';
import 'meaning_sheet.dart';
import 'reader_capsule.dart';
import 'toc_sheet.dart';

/// Halaman baca (board 03 Baca, 11 Akhir bab, 12 Akhir buku). Satu chapter per
/// layar; ujung chapter ada kartu lanjut ke chapter berikutnya, ujung bab
/// terakhir ke layar akhir buku.
class ReaderView extends ConsumerStatefulWidget {
  const ReaderView({super.key, required this.bookId});

  final int bookId;

  @override
  ConsumerState<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<ReaderView>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final ReadingProgressRepository _progress;
  final _clock = ReadingClock(DateTime.now());
  late final _chrome = ReaderChrome(vsync: this);

  /// Setelan Aa terakhir (status bar, garis progres, gaya teks).
  ReaderPrefs _prefs = const ReaderPrefs();

  /// Null sampai posisi tersimpan kebaca.
  int? _chapter;
  int? _chapterId;

  /// Paragraf paling atas yang keliatan + bagiannya yang udah lewat garis
  /// atas; ini yang disimpen.
  _Spot _spot = (index: 0, offset: 0);

  /// Titik yang dituju pas buku dibuka lagi.
  _Spot? _restoreTo;

  /// Nulis posisi ke DB nunggu scroll diem bentar, bukan tiap scroll.
  Timer? _saveLater;
  static const _saveDelay = Duration(milliseconds: 500);

  /// Seberapa jauh chapter ini udah di-scroll, 0..1.
  final _fraction = ValueNotifier<double>(0);

  /// Lagi nampilin layar akhir buku.
  bool _finished = false;

  /// Sheet dari kapsul (daftar isi / Aa) lagi kebuka: kapsul atas tetep
  /// keliatan di atas scrim, tombolnya kuning. [_lastSheet] nentuin warna
  /// scrim, termasuk pas lagi fade out.
  bool _sheetOpen = false;
  _Sheet _lastSheet = _Sheet.toc;

  /// Teks bab yang lagi tampil; diganti tiap pindah bab.
  var _text = GlobalKey<_ChapterTextState>();

  /// Grup yang lagi dibuka di sheet Artinya.
  int? _openGroup;

  @override
  void initState() {
    super.initState();
    _progress = ref.read(readingProgressRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _progress.markOpened(widget.bookId).ignore();
    _chrome.visible.addListener(_syncStatusBar);
  }

  /// Status bar ngumpet bareng kapsul.
  void _syncStatusBar() => SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: _chrome.visible.value || !_prefs.hideStatusBar
        ? SystemUiOverlay.values
        : const [SystemUiOverlay.bottom],
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _clock.resume(DateTime.now());
      return;
    }
    _clock.pause(DateTime.now());
    // iOS bisa matiin app kapan aja pas di background: simpen sekarang.
    _saveLater?.cancel();
    _save();
  }

  @override
  void dispose() {
    _saveLater?.cancel();
    _save();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _chrome.dispose();
    _fraction.dispose();
    super.dispose();
  }

  void _save() {
    final seconds = _clock.take(DateTime.now());
    if (seconds > 0) {
      _progress.addReadingTime(widget.bookId, seconds).ignore();
    }
    final chapterId = _chapterId;
    if (chapterId == null) return;
    _progress.save(widget.bookId, (
      chapterId: chapterId,
      paragraphIndex: _spot.index,
      paragraphOffset: _spot.offset,
    )).ignore();
  }

  void _goTo(ReaderBook book, int chapter) => setState(() {
    _text = GlobalKey();
    _chrome.show(); // awal bab
    _finished = false;
    _chapter = chapter;
    _chapterId = book.chapters[chapter].id;
    _spot = (index: 0, offset: 0);
    _restoreTo = null;
    _fraction.value = 0;
    _saveLater?.cancel();
    _save();
  });

  Future<void> _openToc(ReaderBook book) async {
    final i = _chapter!;
    final ch = book.chapters[i];
    final percent =
        (bookProgress(
                  charOffset: ch.charOffset,
                  chapterChars: ch.chars,
                  fraction: _fraction.value,
                  totalChars: book.totalChars,
                ) *
                100)
            .floor();
    final picked = await _withSheet(
      _Sheet.toc,
      () => showTocSheet(context, book: book, current: i, percent: percent),
    );
    if (picked != null && picked != _chapter && mounted) _goTo(book, picked);
  }

  /// Tap paragraf → sheet Artinya buat grupnya. Kapsul ngumpet, halaman naik
  /// barengan sheet. Ditutup: kalau udah pake "Lanjut", halaman diem di grup
  /// terakhir; kalau cuma satu grup, balik ke posisi sebelum sheet dibuka.
  Future<void> _openMeaning(ReaderParagraph p) async {
    final g = p.groupIndex;
    final text = _text.currentState;
    final chapterId = _chapterId;
    if (g == null || text == null || chapterId == null) return;
    _chrome.hide();
    final before = text.pixels;
    final screen = MediaQuery.sizeOf(context).height;
    var sheetTop = screen;
    var opened = 1;
    final group = ValueNotifier<GroupRef>((
      chapterId: chapterId,
      groupIndex: g,
    ));
    setState(() => _openGroup = g);

    await showMeaningSheet(
      context,
      group: group,
      hasNext: (r) => text.groupAfter(r.groupIndex) != null,
      onNext: () {
        final next = text.groupAfter(group.value.groupIndex);
        if (next == null) return;
        opened++;
        group.value = (chapterId: chapterId, groupIndex: next);
        setState(() => _openGroup = next);
        // Abis highlight pindah & keukur, grup berikutnya naik ke atas sheet.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => text.showGroupAbove(next, sheetTop),
        );
      },
      onHeight: (h) {
        sheetTop = screen - h;
        text.showGroupAbove(group.value.groupIndex, sheetTop);
      },
      onSettings: () {
        Navigator.of(context).pop();
        context.push(Routes.settings);
      },
    );
    group.dispose();
    if (!mounted) return;
    setState(() => _openGroup = null);
    if (opened == 1) {
      await text.scrollBack(before);
    } else {
      text.reportPosition();
    }
  }

  /// Buka sheet dari kapsul: kapsul dimunculin & tombolnya kuning selama
  /// sheet kebuka.
  Future<T?> _withSheet<T>(_Sheet sheet, Future<T?> Function() open) async {
    _chrome.show();
    setState(() {
      _sheetOpen = true;
      _lastSheet = sheet;
    });
    final result = await open();
    if (mounted) setState(() => _sheetOpen = false);
    return result;
  }

  /// Sekali aja: buka di chapter & paragraf tersimpan (atau bab 1).
  void _start(ReaderBook book, ReadingPosition? saved) {
    final i = saved == null
        ? -1
        : book.chapters.indexWhere((c) => c.id == saved.chapterId);
    _chapter = i < 0 ? 0 : i;
    _chapterId = book.chapters[_chapter!].id;
    if (i < 0) return;
    _spot = (index: saved!.paragraphIndex, offset: saved.paragraphOffset);
    _restoreTo = _spot;
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(readerBookProvider(widget.bookId));
    final saved = ref.watch(readingPositionProvider(widget.bookId));
    _chrome.reduceMotion = MediaQuery.disableAnimationsOf(context);
    _prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    ref.listen(readerPrefsProvider, (_, _) => _syncStatusBar());
    return Scaffold(
      body: Listener(
        // Scroll & tap sama-sama mulai dari sini.
        onPointerDown: (_) => _clock.interact(DateTime.now()),
        child: switch ((book, saved)) {
          (AsyncData(value: final b?), AsyncData(value: final pos))
              when b.chapters.isNotEmpty =>
            () {
              if (_chapter == null) _start(b, pos);
              final i = _chapter!;
              if (_finished) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: SafeArea(
                        bottom: false,
                        child: BookEndView(
                          book: b,
                          onClose: () => context.pop(),
                          onRestart: () => _goTo(b, 0),
                        ),
                      ),
                    ),
                    if (_prefs.showProgressLine)
                      const ReaderProgressLine(progress: 1),
                  ],
                );
              }
              final ch = b.chapters[i];
              return Stack(
                children: [
                  Positioned.fill(
                    child: _ChapterText(
                      key: _text,
                      book: b,
                      index: i,
                      fraction: _fraction,
                      chrome: _chrome,
                      prefs: _prefs,
                      restoreTo: _restoreTo,
                      onPosition: (spot) {
                        _spot = spot;
                        _saveLater?.cancel();
                        _saveLater = Timer(_saveDelay, _save);
                      },
                      onParagraphTap: _openMeaning,
                      openGroup: _openGroup,
                      onNext: i + 1 < b.chapters.length
                          ? () => _goTo(b, i + 1)
                          : () {
                              // Posisi tersimpan = ujung buku, rak: "Kelar!".
                              final last =
                                  _text.currentState?._paras.lastOrNull;
                              if (last != null) {
                                _spot = (index: last.index, offset: 1);
                              }
                              _save(); // waktu baca terbaru buat rekapnya
                              _chrome.show(); // status bar balik
                              setState(() => _finished = true);
                            },
                    ),
                  ),
                  Positioned.fill(
                    child: ValueListenableBuilder(
                      valueListenable: _fraction,
                      builder: (context, f, _) {
                        final progress = bookProgress(
                          charOffset: ch.charOffset,
                          chapterChars: ch.chars,
                          fraction: f,
                          totalChars: b.totalChars,
                        );
                        final left = ((1 - f) * ch.chars).round();
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedOpacity(
                                  opacity: _sheetOpen ? 1 : 0,
                                  duration: _sheetOpen
                                      ? Motion.sheetOpen
                                      : Motion.sheetClose,
                                  child: ColoredBox(
                                    // Aa: tipis, teks tetep keliatan buat
                                    // preview setelan.
                                    color: _lastSheet == _Sheet.aa
                                        ? context.stabilo.scrimSoft
                                        : context.stabilo.scrim,
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: ReaderCapsules(
                                chrome: _chrome,
                                top: ReaderTopCapsule(
                                  title: b.title,
                                  subtitle: 'Bab ${i + 1} · ${ch.title}',
                                  onBack: () => context.pop(),
                                  onToc: () => _openToc(b),
                                  onAa: () => _withSheet(
                                    _Sheet.aa,
                                    () => showAaSheet(context),
                                  ),
                                  tocOpen:
                                      _sheetOpen && _lastSheet == _Sheet.toc,
                                  aaOpen: _sheetOpen && _lastSheet == _Sheet.aa,
                                ),
                                bottom: ReaderBottomCapsule(
                                  progress: progress,
                                  label: f >= 0.999
                                      ? 'Bab ${i + 1} beres'
                                      : '±${readingMinutes(left)} mnt lagi',
                                ),
                              ),
                            ),
                            if (_prefs.showProgressLine)
                              ReaderProgressLine(progress: progress),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            }(),
          (AsyncLoading(), _) || (_, AsyncLoading()) => _bare(),
          _ => _bare('Yah, bukunya gagal kebuka'),
        },
      ),
    );
  }

  /// Belum ada buku buat ditampilin: kapsul atas buat balik doang.
  Widget _bare([String? message]) => Stack(
    children: [
      if (message != null)
        Center(
          child: Text(
            message,
            style: StabiloType.body.copyWith(color: context.stabilo.ink2),
          ),
        ),
      Positioned.fill(
        child: ReaderCapsules(
          chrome: _chrome,
          top: ReaderTopCapsule(title: '', onBack: () => context.pop()),
        ),
      ),
    ],
  );
}

class _ChapterText extends ConsumerStatefulWidget {
  const _ChapterText({
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
  });

  final ReaderBook book;
  final int index;
  final ValueNotifier<double> fraction;
  final ReaderChrome chrome;
  final ReaderPrefs prefs;

  /// Titik yang langsung dituju pas kebuka (posisi tersimpan).
  final _Spot? restoreTo;

  /// Titik paling atas yang keliatan, tiap user selesai scroll.
  final ValueChanged<_Spot> onPosition;

  /// Tap paragraf → sheet Artinya.
  final ValueChanged<ReaderParagraph> onParagraphTap;

  /// Grup yang lagi dibuka di sheet Artinya: distabilo, scrim dibolongin di
  /// situ.
  final int? openGroup;
  final VoidCallback onNext;

  @override
  ConsumerState<_ChapterText> createState() => _ChapterTextState();
}

class _ChapterTextState extends ConsumerState<_ChapterText>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();

  /// Lanjut baca: kotak grup tempat posisi tersimpan (koordinat isi bab),
  /// dikasih kilatan stabilo sekali.
  Rect? _mark;
  final _contentKey = GlobalKey();
  late final _flash = AnimationController(vsync: this, duration: Motion.flash)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() => _mark = null);
    });
  Timer? _introTimer;
  Timer? _markTimer;

  /// 0 → 60% → 0 (board: tahan di puncak, turun pelan).
  static final _flashCurve = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0), weight: 6),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 12,
    ),
    TweenSequenceItem(tween: ConstantTween(1), weight: 40),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 42,
    ),
  ]);

  /// Satu key per paragraf (indeks paragraf di DB) buat ngukur & lompat.
  // ponytail: satu chapter dirender utuh (Column), bukan lazy. Aman buat
  // chapter ratusan paragraf; ganti ke list yang bisa lompat ke item kalau
  // ada buku dengan chapter raksasa yang kerasa berat.
  final _keys = <int, GlobalKey>{};
  bool _restored = false;

  /// Scroll dari jari (bukan lompatan restore) yang belum dilaporin.
  bool _userScrolled = false;

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
  _Spot? _topSpot(List<ReaderParagraph> paras) {
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

  /// Paragraf terakhir yang dirender, buat ngukur posisi pas setelan Aa
  /// diganti (layout lama masih ada di [didUpdateWidget]).
  List<ReaderParagraph> _paras = const [];

  @override
  void didUpdateWidget(_ChapterText old) {
    super.didUpdateWidget(old);
    final p = widget.prefs;
    final changed =
        p.fontSize != old.prefs.fontSize ||
        p.font != old.prefs.font ||
        p.lineHeight != old.prefs.lineHeight ||
        p.marginWidth != old.prefs.marginWidth;
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
  bool _place(_Spot spot, double y) {
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
    if (spot != null && _place(spot, MediaQuery.sizeOf(context).height / 3)) {
      _greet(paras, spot);
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

  /// Balik ke posisi sebelum sheet dibuka.
  Future<void> scrollBack(double to) =>
      _animateTo(to, Motion.sheetClose, Motion.sheetCloseCurve);

  Future<void> _animateTo(double to, Duration d, Curve curve) {
    final p = _scroll.position;
    final target = to.clamp(p.minScrollExtent, p.maxScrollExtent);
    if ((target - p.pixels).abs() < 0.5) return Future.value();
    return _scroll.animateTo(
      target,
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : d,
      curve: curve,
    );
  }

  /// Simpen titik yang sekarang di atas (abis halaman digeser sheet).
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
  void _greet(List<ReaderParagraph> paras, _Spot spot) {
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
    _mark = Rect.fromLTRB(
      rect.left - Space.s3,
      rect.top - Space.s2,
      rect.right + Space.s3,
      rect.bottom + Space.s2,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _markTimer = Timer(Motion.flashReduced, () {
        if (mounted) setState(() => _mark = null);
      });
    } else {
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _markTimer?.cancel();
    _flash.dispose();
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
    final loaded = paragraphs is AsyncData;
    final paras = switch (paragraphs) {
      AsyncData(:final value) => _withoutTitleHeading(value, chapter.title),
      _ => const <ReaderParagraph>[],
    };
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
                final edges = readerEdgeFade(pad, widget.chrome.hidden.value);
                return EdgeFadeScroll(
                  top: edges.top,
                  bottom: edges.bottom,
                  child: child!,
                );
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is UserScrollNotification &&
                      n.direction != ScrollDirection.idle) {
                    _userScrolled = true;
                    _introTimer?.cancel(); // udah pegang kendali sendiri
                  } else if (n is ScrollUpdateNotification &&
                      (_userScrolled || n.dragDetails != null)) {
                    _moveChrome(n, paras);
                  } else if (n is ScrollEndNotification && _userScrolled) {
                    _userScrolled = false;
                    widget.chrome.release();
                    final spot = _topSpot(paras);
                    if (spot != null) widget.onPosition(spot);
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
                      pad.top + readerTextTop,
                      widget.prefs.marginWidth,
                      pad.bottom + readerTextBottom,
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
                              label: 'Grup paragraf yang lagi dibuka',
                              child: DecoratedBox(
                                key: const ValueKey('open-group'),
                                decoration: BoxDecoration(
                                  color: c.highlight,
                                  borderRadius: BorderRadius.circular(Radii.md),
                                ),
                              ),
                            ),
                          ),
                        if (_mark != null)
                          Positioned.fromRect(
                            rect: _mark!,
                            child: _markWidget(c),
                          ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(bottom: gap),
                              child: _ChapterHeading(
                                number: widget.index + 1,
                                title: chapter.title,
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
                                    ParagraphType.paragraph => Text(
                                      p.text,
                                      style:
                                          p.groupIndex == open && open != null
                                          ? onOpen
                                          : reading,
                                    ),
                                    ParagraphType.heading => Semantics(
                                      header: true,
                                      child: Text(
                                        p.text,
                                        style: StabiloType.titleSm.copyWith(
                                          color: c.ink,
                                        ),
                                      ),
                                    ),
                                    ParagraphType.sceneBreak => Center(
                                      child: Text(
                                        '* * *',
                                        semanticsLabel: 'Pemisah adegan',
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
                                child: _ChapterEnd(
                                  chapterId: chapter.id,
                                  number: widget.index + 1,
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
                painter: _ScrimHole(
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
      ],
    );
  }

  /// Penanda "terakhir lo baca di sini": kilatan stabilo, atau garis kiri
  /// kalau Kurangi gerakan nyala.
  Widget _markWidget(StabiloColors c) => Semantics(
    label: 'Terakhir lo baca di sini',
    child: MediaQuery.disableAnimationsOf(context)
        ? Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: c.mark,
                borderRadius: BorderRadius.circular(Radii.full),
              ),
            ),
          )
        : AnimatedBuilder(
            animation: _flash,
            builder: (context, _) => DecoratedBox(
              decoration: BoxDecoration(
                color: c.flash.withValues(
                  alpha: c.flash.a * _flashCurve.evaluate(_flash),
                ),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
            ),
          ),
  );

  /// Heading pertama yang isinya sama kayak judul chapter udah ditampilin di
  /// [_ChapterHeading], gak usah dobel.
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

enum _Sheet { toc, aa }

/// Scrim sheet Artinya yang bolong di blok grup.
class _ScrimHole extends CustomPainter {
  _ScrimHole({required this.color, required this.hole, super.repaint});

  final Color color;
  final Rect? Function() hole;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    final h = hole();
    if (h != null) {
      path.addRRect(
        RRect.fromRectAndRadius(h, const Radius.circular(Radii.md)),
      );
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  // Bolongnya diukur ulang tiap paint (scroll / highlight pindah).
  @override
  bool shouldRepaint(_ScrimHole old) => true;
}

/// Titik di chapter: indeks paragraf + bagiannya yang udah lewat garis atas.
typedef _Spot = ({int index, double offset});

class _ChapterHeading extends StatelessWidget {
  const _ChapterHeading({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Container(
          height: 26,
          margin: const EdgeInsets.only(top: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(Radii.full),
          ),
          child: Text(
            'Bab $number',
            style: StabiloType.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: c.onAccent,
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: StabiloType.titleMd.copyWith(color: c.ink),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChapterEnd extends ConsumerWidget {
  const _ChapterEnd({
    required this.chapterId,
    required this.number,
    required this.next,
    required this.nextNumber,
    required this.total,
    required this.onNext,
  });

  final int chapterId;
  final int number;

  /// Null = ini bab terakhir; tombolnya ke layar akhir buku.
  final ChapterInfo? next;
  final int nextNumber;
  final int total;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.stabilo;
    final light = Theme.of(context).brightness == Brightness.light;
    final translated = ref.watch(chapterTranslatedProvider(chapterId)).value;
    final next = this.next;
    return Semantics(
      container: true,
      label: 'Bab selesai',
      child: Container(
        padding: const EdgeInsets.all(Space.s5),
        decoration: BoxDecoration(
          color: c.sheet,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: light ? c.track : c.muted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s3,
          children: [
            Row(
              spacing: Space.s2,
              children: [
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: c.muted,
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      AppIcon(AppIcons.check, size: 12, color: c.ink),
                      Text(
                        'Bab $number kelar',
                        style: StabiloType.tag.copyWith(
                          color: c.ink,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (translated != null && translated > 0)
                  Text(
                    '$translated paragraf diterjemahin',
                    style: StabiloType.caption.copyWith(color: c.ink2),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.s1,
              children: [
                Text(
                  next == null
                      ? 'Itu tadi bab terakhir!'
                      : 'Lanjut ke ${next.title}?',
                  style: StabiloType.titleMd.copyWith(color: c.ink),
                ),
                Text(
                  next == null
                      ? 'Bukunya kelar, tinggal satu tap lagi'
                      : 'Bab $nextNumber dari $total · ±${readingMinutes(next.chars)} menit',
                  style: StabiloType.caption.copyWith(
                    fontSize: 14,
                    color: c.ink2,
                  ),
                ),
              ],
            ),
            AppButton.primary(
              label: 'Lanjut, gas',
              icon: AppIcons.next,
              iconAfter: true,
              onPressed: onNext,
            ),
            Center(
              child: TextButton(
                onPressed: () => context.pop(),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, Layout.touch),
                  foregroundColor: c.ink2,
                  textStyle: StabiloType.label.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Udahan dulu, balik ke rak'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
