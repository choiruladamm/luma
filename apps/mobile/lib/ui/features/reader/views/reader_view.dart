import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/repositories/reading_progress_repository.dart';
import '../../../../domain/models/book.dart';
import '../../../../domain/reading.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../view_models/reader_view_model.dart';
import 'book_end_view.dart';
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

  /// Toggle "Sembunyiin jam & baterai" & "Tampilin garis progres" di Aa
  /// (#18); sementara pake default-nya.
  static const _hideStatusBar = true;
  static const _showProgressLine = true;

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

  /// Sheet daftar isi lagi kebuka: kapsul atas tetep keliatan di atas scrim,
  /// tombolnya kuning.
  bool _tocOpen = false;

  @override
  void initState() {
    super.initState();
    _progress = ref.read(readingProgressRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _progress.markOpened(widget.bookId).ignore();
    _chrome.visible.addListener(_syncStatusBar);
  }

  /// Status bar ngumpet bareng kapsul.
  void _syncStatusBar() {
    if (!_hideStatusBar) return;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: _chrome.visible.value
          ? SystemUiOverlay.values
          : const [SystemUiOverlay.bottom],
    );
  }

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
    if (_hideStatusBar) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
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
    _chrome.show();
    setState(() => _tocOpen = true);
    final picked = await showTocSheet(
      context,
      book: book,
      current: i,
      percent: percent,
    );
    if (!mounted) return;
    setState(() => _tocOpen = false);
    if (picked != null && picked != _chapter) _goTo(book, picked);
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
                    if (_showProgressLine)
                      const ReaderProgressLine(progress: 1),
                  ],
                );
              }
              final ch = b.chapters[i];
              return Stack(
                children: [
                  Positioned.fill(
                    child: _ChapterText(
                      key: ValueKey(ch.id),
                      book: b,
                      index: i,
                      fraction: _fraction,
                      chrome: _chrome,
                      restoreTo: _restoreTo,
                      onPosition: (spot) {
                        _spot = spot;
                        _saveLater?.cancel();
                        _saveLater = Timer(_saveDelay, _save);
                      },
                      // Sheet Artinya nyusul di #23.
                      onParagraphTap: (_) {},
                      onNext: i + 1 < b.chapters.length
                          ? () => _goTo(b, i + 1)
                          : () {
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
                                  opacity: _tocOpen ? 1 : 0,
                                  duration: _tocOpen
                                      ? Motion.sheetOpen
                                      : Motion.sheetClose,
                                  child: ColoredBox(
                                    color: context.stabilo.scrim,
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
                                  tocOpen: _tocOpen,
                                ),
                                bottom: ReaderBottomCapsule(
                                  progress: progress,
                                  label: f >= 0.999
                                      ? 'Bab ${i + 1} beres'
                                      : '±${readingMinutes(left)} mnt lagi',
                                ),
                              ),
                            ),
                            if (_showProgressLine)
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
    required this.restoreTo,
    required this.onPosition,
    required this.onParagraphTap,
    required this.onNext,
  });

  final ReaderBook book;
  final int index;
  final ValueNotifier<double> fraction;
  final ReaderChrome chrome;

  /// Titik yang langsung dituju pas kebuka (posisi tersimpan).
  final _Spot? restoreTo;

  /// Titik paling atas yang keliatan, tiap user selesai scroll.
  final ValueChanged<_Spot> onPosition;

  /// Tap paragraf → sheet Artinya.
  final ValueChanged<ReaderParagraph> onParagraphTap;
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

  /// Taruh titik tersimpan di ±⅓ tinggi layar, biar ada konteks di atasnya.
  void _restore(List<ReaderParagraph> paras) {
    final spot = widget.restoreTo;
    final box = spot == null ? null : _box(spot.index);
    if (box != null && _scroll.hasClients) {
      final p = _scroll.position;
      final point =
          box.localToGlobal(Offset.zero).dy + spot!.offset * box.size.height;
      final target = p.pixels + point - MediaQuery.sizeOf(context).height / 3;
      _scroll.jumpTo(target.clamp(p.minScrollExtent, p.maxScrollExtent));
      _greet(paras, spot);
    }
    if (_scroll.hasClients) _track();
    // Baru keliatan setelah di posisi yang bener (lihat AnimatedOpacity).
    setState(() => _restored = true);
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
    Rect? rect;
    for (final p in paras.where((p) => p.groupIndex == group)) {
      final box = _box(p.index);
      if (box == null) continue;
      final r = box.localToGlobal(Offset.zero, ancestor: content) & box.size;
      rect = rect?.expandToInclude(r) ?? r;
    }
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
    final reading = StabiloType.forBrightness(
      StabiloType.reading,
      Theme.of(context).brightness,
    ).copyWith(color: c.ink);
    final gap = reading.fontSize!; // 1em antar paragraf
    final pad = MediaQuery.paddingOf(context);
    final loaded = paragraphs is AsyncData;
    final paras = switch (paragraphs) {
      AsyncData(:final value) => _withoutTitleHeading(value, chapter.title),
      _ => const <ReaderParagraph>[],
    };

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
    return AnimatedOpacity(
      opacity: _restored ? 1 : 0,
      duration: fade,
      curve: Curves.easeOut,
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
          onTap: widget.chrome.toggle,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              Layout.margin,
              pad.top + readerTextTop,
              Layout.margin,
              pad.bottom + readerTextBottom,
            ),
            child: Stack(
              key: _contentKey,
              children: [
                if (_mark != null)
                  Positioned.fromRect(rect: _mark!, child: _markWidget(c)),
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
                          key: _keys.putIfAbsent(p.index, GlobalKey.new),
                          child: switch (p.type) {
                            // Kotak paragraf selebar kolom, termasuk sisa baris
                            // pendek. Sela antar paragraf & margin = area kosong.
                            ParagraphType.paragraph => GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onParagraphTap(p),
                              child: Text(p.text, style: reading),
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
