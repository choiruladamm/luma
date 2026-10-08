import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/ai_prompt.dart';
import '../../../../domain/models/ai_reply.dart';
import '../../../../domain/models/reader_prefs.dart';
import '../../../../domain/pacing.dart';
import '../../../../domain/stream_text.dart';
import '../../../core/theme/reader_typography.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/ai_status.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';
import '../../../core/widgets/sheet.dart';
import '../../../core/widgets/tag.dart';
import '../../../core/widgets/toast.dart';
import '../view_models/breakdown_view_model.dart';
import '../view_models/reader_view_model.dart';
import 'meaning_chrome.dart';

/// Sheet Artinya (board 05 hasil, 06 error, 09 udah disalin, 10 API key
/// kosong, "Artinya streaming · Opsi B" + "· perilaku"). [group] = grup yang lagi dibuka; "Lanjut" manggil
/// [onNext] yang mindahin [group] ke grup berikutnya. [onHeight] dipanggil
/// sekali dengan tinggi sheet (tetap 528 di 844, semua state), biar halaman
/// di belakang bisa nyesuain. Barrier transparan: scrim (yang bolongin grup)
/// digambar halaman baca. [onProgress] (0–1) dipanggil pas sheet di-scroll:
/// seberapa jauh terjemahan udah kebaca, biar isi card kuning ngikutin.
/// [onBreakdown]: entri "Masih bingung? Bedahin" di akhir isi di-tap.
Future<void> showMeaningSheet(
  BuildContext context, {
  required ValueListenable<GroupRef> group,
  required bool Function(GroupRef) hasNext,
  required VoidCallback onNext,
  required ValueChanged<double> onHeight,
  required ValueChanged<double> onProgress,
  required VoidCallback onClosing,
  required VoidCallback onSettings,
  required ValueChanged<GroupRef> onBreakdown,
}) {
  final screen = MediaQuery.sizeOf(context).height;
  final height = screen * Layout.artinyaHeight;
  WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  final sheet = DraggableScrollableController();
  return showAppSheet<void>(
    context,
    maxHeight: 1, // tingginya diatur DraggableScrollableSheet
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    // Material bawaan sheet (transparan) nutupin seluruh layar dan nelen tap,
    // jadi tap area kosong di atas sheet ditangkep lapisan di belakangnya.
    builder: (context) => _ClosingWatcher(
      onClosing: onClosing,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          DraggableScrollableSheet(
            // Tarik turun di isi pas offset 0 nutup sheet; di grabber lewat [_Drag].
            controller: sheet,
            initialChildSize: Layout.artinyaHeight,
            minChildSize: 0,
            maxChildSize: Layout.artinyaHeight,
            snap: true,
            builder: (context, scroll) {
              final theme = Theme.of(context).bottomSheetTheme;
              return PrimaryScrollController(
                controller: scroll,
                child: Material(
                  key: const ValueKey('meaning-sheet'),
                  color: theme.modalBackgroundColor,
                  shape: theme.shape,
                  clipBehavior: Clip.antiAlias,
                  child: _Drag(
                    sheet: sheet,
                    screen: screen,
                    child: ValueListenableBuilder(
                      valueListenable: group,
                      builder: (context, g, _) => MeaningSheet(
                        key: ValueKey(g),
                        group: g,
                        onNext: hasNext(g) ? onNext : null,
                        onProgress: onProgress,
                        onSettings: onSettings,
                        onBreakdown: () => onBreakdown(g),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  ).whenComplete(sheet.dispose);
}

/// Ngabarin [onClosing] begitu route sheet mulai nutup, lewat tombol, tap di
/// luar, atau tarik turun.
class _ClosingWatcher extends StatefulWidget {
  const _ClosingWatcher({required this.onClosing, required this.child});

  final VoidCallback onClosing;
  final Widget child;

  @override
  State<_ClosingWatcher> createState() => _ClosingWatcherState();
}

class _ClosingWatcherState extends State<_ClosingWatcher> {
  Animation<double>? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation == _animation) return;
    _animation?.removeStatusListener(_listen);
    _animation = animation?..addStatusListener(_listen);
  }

  void _listen(AnimationStatus status) {
    if (status == AnimationStatus.reverse) widget.onClosing();
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_listen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Drag di grabber: sheet ngikutin jari ke bawah; dilepas, nutup kalau
/// di-fling atau udah ditarik jauh, kalau nggak balik ke atas. (Grabber
/// lapisan di atas isi, jadi dragnya gak sampe ke scroll view.)
class _Drag extends InheritedWidget {
  const _Drag({
    required this.sheet,
    required this.screen,
    required super.child,
  });

  final DraggableScrollableController sheet;
  final double screen;

  static _Drag of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Drag>()!;

  void update(DragUpdateDetails d) {
    if (!sheet.isAttached) return;
    sheet.jumpTo(
      (sheet.size - d.delta.dy / screen).clamp(0.0, Layout.artinyaHeight),
    );
  }

  void end(BuildContext context, DragEndDetails d) {
    if (!sheet.isAttached) return;
    final close =
        (d.primaryVelocity ?? 0) >= Layout.sheetDismissFling ||
        sheet.size < Layout.artinyaHeight * Layout.sheetDismissRatio;
    if (close) {
      Navigator.of(context).pop();
    } else {
      sheet.animateTo(
        Layout.artinyaHeight,
        duration: Motion.sheetClose,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  bool updateShouldNotify(_Drag old) => false;
}

class MeaningSheet extends ConsumerStatefulWidget {
  const MeaningSheet({
    super.key,
    required this.group,
    required this.onNext,
    required this.onProgress,
    required this.onSettings,
    required this.onBreakdown,
  });

  final GroupRef group;

  /// Null = grup terakhir di bab ini.
  final VoidCallback? onNext;
  final ValueChanged<double> onProgress;
  final VoidCallback onSettings;
  final VoidCallback onBreakdown;

  @override
  ConsumerState<MeaningSheet> createState() => _MeaningSheetState();
}

class _MeaningSheetState extends ConsumerState<MeaningSheet> {
  bool _copied = false;

  void _close() => Navigator.of(context).pop();

  Future<void> _copy(AiReply reply) async {
    await Clipboard.setData(
      ClipboardData(text: reply.translations.join('\n\n')),
    );
    if (!mounted) return;
    setState(() => _copied = true);
    showOverlayToast(
      context,
      'Udah disalin, tinggal paste',
      bottom: MediaQuery.paddingOf(context).bottom + 68,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(groupAiStreamProvider(widget.group));
    // Teks isi ikut Aa; ganti pengaturan langsung kebawa tanpa nutup sheet.
    final prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    final typo = ReaderTypography(prefs, Theme.of(context).brightness);
    void retry() => ref.invalidate(groupAiStreamProvider(widget.group));
    return switch (ai) {
      AiStream(
        phase: AiPhase.failed,
        error: AiException(error: AiError.noApiKey),
      ) =>
        _NoKey(onClose: _close, onSettings: widget.onSettings),
      AiStream(phase: AiPhase.failed, :final error) => _Failed(
        code: _errorCode(error ?? 'error'),
        onClose: _close,
        onRetry: retry,
      ),
      _ => _Answer(
        typo: typo,
        ai: ai,
        copied: _copied,
        onCopy: () => _copy(
          AiReply(
            translations: ai.draft.translations,
            meaning: ai.draft.meaning ?? '',
          ),
        ),
        onNext: widget.onNext,
        onProgress: widget.onProgress,
        onClose: _close,
        onRetry: retry,
        breakdown: _BreakdownEntry(
          group: widget.group,
          fade: !ai.cached,
          onTap: widget.onBreakdown,
        ),
      ),
    };
  }

  /// Kode kecil buat debug di state error.
  static String _errorCode(Object error) => switch (error) {
    AiException(error: AiError.timeout) => 'timeout · 30 detik',
    AiException(error: AiError.network) => 'offline / gak nyambung',
    AiException(error: AiError.http, :final status)
        when status == 401 || status == 403 =>
      'HTTP $status · key ditolak',
    AiException(error: AiError.http, status: 402) => 'HTTP 402 · saldo abis',
    AiException(error: AiError.http, :final status) => 'HTTP $status',
    AiException(error: AiError.invalidResponse) => 'jawaban AI gak valid',
    _ => 'error',
  };
}

/// Rangka semua state: isi scroll setinggi sheet (528) dengan padding atas 91
/// / bawah 102, header + grabber + tombol lapisan di atasnya (board Ngumpet ·
/// Opsi A). Scroll view-nya pakai controller dari DraggableScrollableSheet
/// (`PrimaryScrollController`), jadi tarik turun di offset 0 nutup sheet.
/// [hideable]: header dan tombol ngumpet ngikutin scroll jari ([MeaningChrome]).
class _ScrollFrame extends StatefulWidget {
  const _ScrollFrame({
    required this.header,
    required this.content,
    required this.actions,
    this.margin = 0,
    this.gap = Space.s4,
    this.hideable = false,
    this.locked = false,
    this.frozen = false,
    this.topInset = Layout.artinyaHeader,
  });

  final Widget header;
  final List<Widget> content;
  final List<Widget> actions;

  /// Margin teks Aa. Padding dasar sheet (24) jadi batas bawahnya; isi cuma
  /// dilebarin kalau margin-nya lebih besar (Lega 32).
  final double margin;
  final double gap;
  final bool hideable;

  /// Lagi streaming: tombol dikunci keliatan, header ikut isi 1:1 kayak
  /// bagian dari isi scroll.
  final bool locked;

  /// Belum ada teks (nunggu token): isi gak bisa di-scroll. Nutup tetep
  /// lewat X, grabber, atau tap di atas sheet.
  final bool frozen;

  /// Jarak isi dari atas sheet (ruang buat header yang jadi lapisan).
  final double topInset;

  @override
  State<_ScrollFrame> createState() => _ScrollFrameState();
}

class _ScrollFrameState extends State<_ScrollFrame>
    with TickerProviderStateMixin {
  late final _chrome = MeaningChrome(vsync: this);

  /// Scroll-nya dari jari (bukan scroll programatik).
  bool _user = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chrome.reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncEnabled();
  }

  @override
  void didUpdateWidget(_ScrollFrame old) {
    super.didUpdateWidget(old);
    _syncEnabled();
  }

  /// Gak pernah ngumpet kalau VoiceOver nyala, bukan state hasil, atau lagi
  /// streaming. Abis streaming, header yang udah ke-scroll keluar tetep di
  /// luar (aturan ngumpet biasa nerusin).
  void _syncEnabled() {
    _chrome.enabled =
        widget.hideable &&
        !widget.locked &&
        !MediaQuery.accessibleNavigationOf(context);
    if (!_chrome.enabled && !widget.locked) _chrome.show();
    if (widget.locked) _chrome.actions.value = 0;
  }

  @override
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (widget.locked) {
      if (n is ScrollUpdateNotification) {
        _chrome.header.value = (n.metrics.pixels / Layout.artinyaHeader).clamp(
          0.0,
          1.0,
        );
      }
      return false;
    }
    switch (n) {
      case UserScrollNotification():
        _user = n.direction != ScrollDirection.idle;
      case ScrollUpdateNotification() when _user || n.dragDetails != null:
        _chrome.scrolled(
          pixels: n.metrics.pixels,
          max: n.metrics.maxScrollExtent,
          delta: n.scrollDelta ?? 0,
        );
      case ScrollEndNotification():
        if (_user) _chrome.release(n.metrics.pixels);
        _user = false;
      default:
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final pad = Layout.sheetPadding;
    final inset = math.max(0.0, widget.margin - pad.left);
    final reduced = _chrome.reduceMotion;
    // Titik tempel header: di bawah grabber (padding atas 10 + 5 + 16).
    final headerTop = Layout.artinyaHeader - Space.s4 - Layout.touch;
    final headerBottom = Layout.artinyaHeader - Space.s4; // header 44 tinggi
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          // Tepi isi ikut animasi chrome: fade atas mulai di bawah header
          // (atau di bawah grabber kalau header ngumpet), fade bawah cuma ada
          // selama tombol keliatan; tombol ngumpet = edge-to-edge.
          child: AnimatedBuilder(
            animation: Listenable.merge([_chrome.header, _chrome.actions]),
            builder: (context, scroll) {
              final hidden = _chrome.header.value;
              final away = _chrome.actions.value;
              return EdgeFadeScroll(
                top: EdgeFadeSide(
                  20,
                  clear: math.max(
                    Layout.artinyaGrabberZone,
                    headerBottom - Layout.artinyaHeader * hidden,
                  ),
                ),
                // Tombol + safe area (86) bening, fade 20pt tepat di atasnya.
                bottom: EdgeFadeSide(
                  20 * (1 - away),
                  clear: (Layout.artinyaActions - Space.s4) * (1 - away),
                ),
                child: scroll!,
              );
            },
            child: SingleChildScrollView(
              primary: true,
              physics: widget.frozen
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                pad.left,
                widget.topInset,
                pad.right,
                Layout.artinyaActions,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: widget.gap,
                  children: widget.content,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: headerTop,
          left: pad.left,
          right: pad.right,
          child: _Chrome(
            animation: _chrome.header,
            travel: -Layout.artinyaHeader,
            reduced: reduced,
            child: widget.header,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Builder(
            builder: (context) {
              final drag = _Drag.of(context);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: drag.update,
                onVerticalDragEnd: (d) => drag.end(context, d),
                child: Padding(
                  padding: EdgeInsets.only(top: pad.top, bottom: Space.s4),
                  child: const SheetGrabber(),
                ),
              );
            },
          ),
        ),
        Positioned(
          left: pad.left,
          right: pad.right,
          bottom: pad.bottom,
          child: _Chrome(
            animation: _chrome.actions,
            travel: Layout.artinyaActions,
            reduced: reduced,
            child: Row(spacing: 10, children: widget.actions),
          ),
        ),
      ],
    );
  }
}

/// Geser [child] sejauh [travel] ngikutin [animation] (0 keliatan, 1
/// ngumpet). Kurangi gerakan: gak geser, cuma fade. Yang ngumpet gak bisa
/// di-tap dan gak kebaca VoiceOver.
class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.animation,
    required this.travel,
    required this.reduced,
    required this.child,
  });

  final Animation<double> animation;
  final double travel;
  final bool reduced;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final v = animation.value;
      final hidden = v >= 1;
      return ExcludeSemantics(
        excluding: hidden,
        child: IgnorePointer(
          ignoring: v > 0.5,
          child: reduced
              ? Opacity(opacity: 1 - v, child: child)
              : Transform.translate(
                  offset: Offset(0, travel * v),
                  child: child,
                ),
        ),
      );
    },
  );
}

class _Title extends StatelessWidget {
  const _Title(this.text, {required this.closeLabel, required this.onClose});

  final String text;
  final String closeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
    spacing: Space.s3,
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(text, style: StabiloType.titleMd),
        ),
      ),
      CircleButton(
        semanticLabel: closeLabel,
        icon: AppIcons.close,
        onPressed: onClose,
      ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.tag, required this.child});

  final Widget tag;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: Space.s2,
    children: [tag, child],
  );
}

/// Terjemahan + makna, dari nunggu token sampai selesai (board "Artinya
/// streaming · Opsi B" + "· perilaku"), atau langsung jadi kalau dari cache.
/// Satu widget buat semua tahap, jadi pas selesai gak ada loncatan layout dan
/// posisi scroll gak di-reset.
///
/// - Teks keluar ngikutin [Pacer], per frame. Kurangi gerakan: per bagian
///   utuh (satu paragraf, lalu makna), tanpa pudar.
/// - Ujung teks yang lagi ditulis: 4 kata terakhir makin transparan, diem.
///   Selesai → jadi solid pelan. (Deviasi dari board: tanpa fade-in per
///   potongan, satu mekanisme aja.)
/// - Selama belum selesai: tombol dikunci keliatan. Isi gak di-scroll
///   otomatis: tetep di awal terjemahan biar bisa dibaca dari atas sambil
///   sisanya ditulis (deviasi dari board, yang ikut turun).
/// - Kelamaan: kartu di atas isi. Kepotong: teks yang udah masuk + banner,
///   placeholder dibuang.
class _Answer extends StatefulWidget {
  const _Answer({
    required this.typo,
    required this.ai,
    required this.copied,
    required this.onCopy,
    required this.onNext,
    required this.onProgress,
    required this.onClose,
    required this.onRetry,
    required this.breakdown,
  });

  final ReaderTypography typo;
  final AiStream ai;
  final bool copied;
  final VoidCallback onCopy;
  final VoidCallback? onNext;
  final ValueChanged<double> onProgress;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  /// Entri Bedahin, item terakhir isi; cuma pas jawabannya lengkap.
  final Widget breakdown;

  @override
  State<_Answer> createState() => _AnswerState();
}

class _AnswerState extends State<_Answer> with TickerProviderStateMixin {
  final _pacer = Pacer();
  late final _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  int _shown = 0;

  /// Ujung teks: 0 = pudar, 1 = solid.
  late final _solid = AnimationController(
    vsync: this,
    duration: Motion.tailFade,
  );

  /// Jawaban lengkap dan semua hurufnya udah tampil.
  bool _finished = false;

  AiStream get _ai => widget.ai;
  bool get _cut => _ai.phase == AiPhase.cut;
  bool get _writing => !_finished && !_cut;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Answer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Nyalain ticker begitu ada huruf; kepotong = tampilin semua yang masuk.
  /// Dari cache = langsung jadi, tanpa ritme dan tanpa ikut turun.
  void _sync() {
    if (_finished) return;
    final available = _ai.draft.length;
    if (_ai.cached) {
      _finished = true;
      _shown = available;
      _solid.value = 1;
      _ticker.stop();
      return;
    }
    if (_cut) {
      _pacer.finish(available);
      _shown = available;
      _ticker.stop();
      return;
    }
    if (available > 0 && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    final available = _ai.draft.length;
    final done = _ai.phase == AiPhase.done;
    final shown = MediaQuery.disableAnimationsOf(context)
        ? available
        : _pacer.step(dt, available, done: done);
    final finished = done && shown >= available;
    if (shown == _shown && !finished) return;
    setState(() {
      _shown = shown;
      _finished = finished;
    });
    if (finished) {
      _ticker.stop();
      _solid.animateTo(
        1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.tailFade,
      );
      if (MediaQuery.accessibleNavigationOf(context)) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Artinya udah lengkap',
          TextDirection.ltr,
        );
      }
    }
  }

  /// Kotak tiap terjemahan: akhir yang terakhir nentuin seberapa jauh
  /// terjemahan udah kebaca.
  final _boxes = <GlobalKey>[];
  double _progress = 0;

  GlobalKey _boxKey(int i) {
    while (_boxes.length <= i) {
      _boxes.add(GlobalKey());
    }
    return _boxes[i];
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n is ScrollUpdateNotification) {
      _follow(n.metrics.pixels);
    }
    return false;
  }

  /// Sinkron sheet → isi card: progres baca terjemahan, 0 di awal sheet sampe 1
  /// pas bawah terjemahan terakhir nyampe tepi bawah area isi. Blok makna gak
  /// dihitung: lewat itu progresnya tetap 1. Linear terhadap scroll, jadi
  /// ngikutin jari, dan berlaku juga buat grup satu paragraf panjang.
  void _follow(double pixels) {
    final root = context.findRenderObject();
    final count = math.max(_ai.sources.length, _ai.draft.translations.length);
    if (root is! RenderBox || !root.hasSize || count == 0) return;
    final last = _boxKey(count - 1).currentContext?.findRenderObject();
    if (last is! RenderBox || !last.hasSize) return;
    final visibleBottom =
        root.localToGlobal(Offset.zero).dy +
        root.size.height -
        Layout.artinyaActions;
    final remaining = math.max(
      0.0,
      last.localToGlobal(Offset.zero).dy + last.size.height - visibleBottom,
    );
    // Scroll yang udah dijalanin + sisanya = total sampe terjemahan kebaca.
    final total = pixels + remaining;
    final next = total <= 0 ? 0.0 : (pixels / total).clamp(0.0, 1.0);
    if ((next - _progress).abs() < 0.001) return;
    _progress = next;
    widget.onProgress(next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _solid.dispose();
    super.dispose();
  }

  /// Yang boleh tampil sekarang.
  AiDraft _visible() {
    final draft = _ai.draft;
    if (_finished || _cut) return draft;
    if (!MediaQuery.disableAnimationsOf(context)) return draft.take(_shown);
    // Kurangi gerakan: cuma bagian yang udah utuh.
    if (draft.meaning != null) return AiDraft(translations: draft.translations);
    final whole = math.max(0, draft.translations.length - 1);
    return AiDraft(translations: draft.translations.take(whole).toList());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final typo = widget.typo;
    final style = typo.style.copyWith(color: c.ink);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final writing = _writing;
    final draft = _visible();
    final count = math.max(_ai.sources.length, _ai.draft.translations.length);
    final thinking =
        writing &&
        _ai.draft.length == 0 &&
        (_ai.phase == AiPhase.waiting || _ai.phase == AiPhase.slow);
    // Bagian terakhir yang keliatan = yang lagi ditulis (ujungnya pudar).
    final lastMeaning = draft.meaning != null;
    final last = lastMeaning ? -1 : draft.translations.length - 1;

    Widget text(String t, {required bool isLast}) {
      if (!isLast) return Text(t, style: style);
      final faded = !_cut && !reduced;
      return ExcludeSemantics(
        // VoiceOver baca per bagian yang udah utuh, bukan per huruf.
        excluding: writing,
        child: AnimatedBuilder(
          animation: _solid,
          builder: (context, _) {
            if (!faded || _solid.value >= 1) return Text(t, style: style);
            final split = splitTail(t);
            final alphas = tailAlphas.sublist(
              tailAlphas.length - split.tail.length,
            );
            return Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: split.head),
                  for (final (i, w) in split.tail.indexed)
                    TextSpan(
                      text: w,
                      style: TextStyle(
                        color: c.ink.withValues(
                          alpha: alphas[i] + (1 - alphas[i]) * _solid.value,
                        ),
                      ),
                    ),
                ],
              ),
              style: style,
            );
          },
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Semantics(
        label: writing ? 'Artinya, lagi ditulis' : null,
        child: _ScrollFrame(
          margin: typo.margin,
          hideable: true,
          locked: writing,
          frozen: thinking,
          header: _Title(
            thinking ? 'Bentar, lagi mikir...' : 'Artinya gini nih',
            closeLabel: writing ? 'Batalin' : 'Tutup',
            onClose: widget.onClose,
          ),
          content: [
            if (_ai.phase == AiPhase.slow)
              _SlowCard(onCancel: widget.onClose, onRetry: widget.onRetry),
            _Section(
              tag: const Tag.section('Terjemahan'),
              // Satu blok per paragraf, biar jeda dialognya sama kayak aslinya.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.s2,
                children: [
                  for (var i = 0; i < count; i++)
                    if (i < draft.translations.length)
                      KeyedSubtree(
                        key: _boxKey(i),
                        child: text(draft.translations[i], isLast: i == last),
                      )
                    else if (!_cut && i < _ai.sources.length)
                      KeyedSubtree(
                        key: _boxKey(i),
                        child: _Placeholder(
                          chars: estimateTranslation(_ai.sources[i]),
                          style: style,
                        ),
                      ),
                ],
              ),
            ),
            if (!_cut || lastMeaning)
              _Section(
                tag: const Tag.section(
                  'Maksud penulisnya tuh...',
                  tone: TagTone.pink,
                ),
                child: lastMeaning
                    ? text(draft.meaning!, isLast: true)
                    : _Placeholder(chars: estimatedMeaning, style: style),
              ),
            if (_cut) _CutBanner(onRetry: widget.onRetry),
            if (_finished) widget.breakdown,
          ],
          actions: [
            AnimatedSwitcher(
              duration: reduced ? Duration.zero : Motion.statusSwap,
              child: writing && !_cut && _ai.phase != AiPhase.slow
                  ? StatusButton(
                      key: ValueKey(thinking),
                      label: thinking ? 'Lagi mikir' : 'Lagi nulis',
                    )
                  : AppButton.secondary(
                      key: const ValueKey('copy'),
                      label: widget.copied ? 'Disalin' : 'Salin',
                      icon: widget.copied ? AppIcons.check : AppIcons.copy,
                      onPressed: _finished ? widget.onCopy : null,
                    ),
            ),
            Expanded(
              // Mati selama masih diproses; aktif lagi pas selesai / kepotong.
              child: AppButton.primary(
                label: 'Lanjut',
                icon: AppIcons.down,
                iconAfter: true,
                onPressed: writing ? null : widget.onNext,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder satu bagian yang belum ditulis, kira-kira setinggi teksnya
/// nanti (ikut Aa): baris dari [placeholderRows], tinggi baris = baris teks.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.chars, required this.style});

  final double chars;
  final TextStyle style;

  /// Lebar huruf rata-rata per font + ukuran, diukur sekali.
  static final _widths = <(String?, double?), double>{};
  static const _sample =
      'Sayangku Mr. Bennet, kata istrinya suatu hari, sudah dengar belum '
      'kalau Netherfield Park akhirnya disewa orang?';

  double _charWidth() => _widths[(style.fontFamily, style.fontSize)] ??= () {
    final painter = TextPainter(
      text: TextSpan(text: _sample, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width / _sample.length;
    painter.dispose();
    return width;
  }();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Skeleton(
      widths: placeholderRows(chars, _charWidth(), box.maxWidth),
      lineExtent: style.fontSize! * style.height!,
    ),
  );
}

/// 15 detik belum ada token. Request tetep jalan; token masuk = kartunya
/// ilang sendiri.
class _SlowCard extends StatelessWidget {
  const _SlowCard({required this.onCancel, required this.onRetry});

  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      child: StatusCard(
        color: c.muted,
        line: c.track,
        tile: c.accent,
        icon: AppIcons.clock,
        iconColor: c.onAccent,
        title: 'Agak lama nih...',
        body: 'AI-nya masih mikir. Tungguin bentar lagi, atau coba ulang.',
        actions: [
          Expanded(
            child: AppButton.secondary(
              label: 'Batal',
              height: 40,
              onPressed: onCancel,
            ),
          ),
          Expanded(
            child: AppButton.primary(
              label: 'Coba lagi',
              icon: AppIcons.retry,
              height: 40,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

/// Koneksi putus / mandek di tengah: yang udah masuk tetep di atasnya.
class _CutBanner extends StatelessWidget {
  const _CutBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      child: StatusCard(
        color: c.pinkSoft,
        line: c.pink,
        tile: c.pink,
        icon: AppIcons.offline,
        iconColor: c.onPink,
        title: 'Yah, kepotong di tengah',
        body: 'Koneksinya putus pas lagi nulis. Yang udah masuk tetep di sini.',
        actions: [
          Expanded(
            child: AppButton.primary(
              label: 'Coba lagi',
              icon: AppIcons.retry,
              height: 40,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kotak ikon di pojok state error / API key kosong, dan jarak isi di
/// bawahnya: isi mulai [_tileInset] dari atas sheet (di bawah kotak, lega).
const _tileInset =
    Layout.artinyaHeader - Space.s4 - Layout.touch + IconTile.size + Space.s6;

/// Header state error / API key kosong: kotak ikon kiri, tutup kanan.
class _TileHeader extends StatelessWidget {
  const _TileHeader({required this.tile, required this.onClose});

  final Widget tile;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      tile,
      CircleButton(
        semanticLabel: 'Tutup',
        icon: AppIcons.close,
        onPressed: onClose,
      ),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: Space.s2,
    children: [
      Semantics(header: true, child: Text(title, style: StabiloType.titleMd)),
      Text(body, style: StabiloType.body.copyWith(color: context.stabilo.ink2)),
    ],
  );
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.code,
    required this.onClose,
    required this.onRetry,
  });

  final String code;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      liveRegion: true,
      label: 'Gagal ngambil artinya',
      child: _ScrollFrame(
        gap: 14,
        topInset: _tileInset,
        header: _TileHeader(
          tile: IconTile(icon: AppIcons.offline, bg: c.pink, fg: c.onPink),
          onClose: onClose,
        ),
        content: [
          const _Message(
            title: 'Yah, gagal nih',
            body:
                'Kayaknya koneksi lagi ngadat, atau AI-nya lagi sibuk. Tinggal '
                'coba lagi aja.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Space.s2),
              ),
              child: Text(
                code,
                style: StabiloType.mono.copyWith(fontSize: 12, color: c.ink2),
              ),
            ),
          ),
        ],
        actions: [
          AppButton.secondary(label: 'Nanti aja', onPressed: onClose),
          Expanded(
            child: AppButton.primary(
              label: 'Coba lagi',
              icon: AppIcons.retry,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoKey extends StatelessWidget {
  const _NoKey({required this.onClose, required this.onSettings});

  final VoidCallback onClose;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return _ScrollFrame(
      gap: 14,
      topInset: _tileInset,
      header: _TileHeader(
        tile: IconTile(icon: AppIcons.key, bg: c.accent, fg: c.onAccent),
        onClose: onClose,
      ),
      content: [
        const _Message(
          title: 'Isi API key dulu yuk',
          body:
              'Artinya dibikin AI lewat OpenRouter. Tempel API key lo sekali '
              'aja di Pengaturan, abis itu tinggal tap-tap paragraf.',
        ),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Belum punya? Bikin dulu di '),
              TextSpan(
                text: 'openrouter.ai/keys',
                style: StabiloType.mono.copyWith(fontSize: 13, color: c.ink),
              ),
            ],
          ),
          style: StabiloType.caption.copyWith(
            fontWeight: FontWeight.w400,
            color: c.ink2,
          ),
        ),
      ],
      actions: [
        AppButton.secondary(label: 'Nanti aja', onPressed: onClose),
        Expanded(
          child: AppButton.primary(
            label: 'Buka Pengaturan',
            icon: AppIcons.next,
            iconAfter: true,
            onPressed: onSettings,
          ),
        ),
      ],
    );
  }
}

/// "Masih bingung? Bedahin" di akhir isi sheet (board Opsi C · C1, state B3 /
/// B4): udah pernah dibedah = "Buka bedahan · N bagian". Muncul cuma pas
/// makna lengkap, fade 150ms kalau abis di-stream. Nunggu jumlah bagian dari
/// DB dulu biar copy-nya gak ganti di depan mata.
class _BreakdownEntry extends ConsumerWidget {
  const _BreakdownEntry({
    required this.group,
    required this.fade,
    required this.onTap,
  });

  final GroupRef group;
  final bool fade;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = switch (ref.watch(breakdownSectionsProvider(group))) {
      AsyncData(:final value) => value,
      AsyncError() => 0,
      _ => null,
    };
    if (sections == null) return const SizedBox.shrink();
    final c = context.stabilo;
    final opened = sections > 0;
    final title = opened ? 'Buka bedahan' : 'Masih bingung? Bedahin';
    final subtitle = opened
        ? 'Udah pernah dibedah · ${sections == 1 ? '1 gagasan' : '$sections bagian'}'
        : 'Per bagian, plus tokoh & istilah';
    final entry = Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              spacing: Space.s3,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c.ink,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(
                      opened ? AppIcons.check : AppIcons.list,
                      size: 18,
                      color: c.canvas,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 1,
                    children: [
                      Text(
                        title,
                        style: StabiloType.label.copyWith(
                          fontSize: 16,
                          color: c.ink,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StabiloType.caption.copyWith(
                          fontWeight: FontWeight.w400,
                          color: c.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
                AppIcon(AppIcons.chevron, size: 18, color: c.ink),
              ],
            ),
          ),
        ),
      ),
    );
    if (!fade || MediaQuery.disableAnimationsOf(context)) return entry;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.statusSwap,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: entry,
    );
  }
}
