import 'package:luma/l10n/l10n.dart';

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
import '../../../../data/repositories/ai_key_repository.dart';
import '../../../core/widgets/quota.dart';
import '../../settings/view_models/ai_quota_view_model.dart';
import '../../settings/views/ai_shared.dart';
import 'meaning_chrome.dart';

/// Artinya sheet (boards "05 hasil", "06 error", "09 udah disalin", "10 API key kosong",
/// "Artinya streaming · Opsi B" + "· perilaku"). [group] = the open group; "Lanjut"
/// calls [onNext], which moves [group] to the next group. [onHeight] is called once
/// with the sheet height (fixed 528 on 844, every state) so the page behind can
/// adjust. Transparent barrier: the scrim (which cuts a hole for the group) is drawn
/// by the reading page. [onProgress] (0–1) is called as the sheet scrolls: how far
/// the translation has been read, so the yellow card content follows.
/// [onBreakdown]: the "Masih bingung? Bedahin" entry at the end of the content was tapped.
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
  void Function(GroupRef, String)? onChat,
}) {
  final screen = MediaQuery.sizeOf(context).height;
  final height = screen * Layout.artinyaHeight;
  WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  final sheet = DraggableScrollableController();
  return showAppSheet<void>(
    context,
    maxHeight: 1, // height is managed by DraggableScrollableSheet
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    // The sheet's built-in Material (transparent) covers the whole screen and swallows
    // taps, so a tap on the empty area above the sheet is caught by the layer behind it.
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
            // Dragging down on the content at offset 0 closes the sheet; on the grabber via [_Drag].
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
                        onChat: onChat == null
                            ? null
                            : (translation) => onChat(g, translation),
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

/// Reports [onClosing] as soon as the sheet route starts closing, via the button, a
/// tap outside, or a drag down.
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

/// Drag on the grabber: the sheet follows the finger down; on release it closes if
/// flung or pulled far enough, otherwise returns to the top. (The grabber is a layer
/// above the content, so its drag never reaches the scroll view.)
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
    this.onChat,
  });

  final GroupRef group;

  /// Null = the last group in this chapter.
  final VoidCallback? onNext;
  final ValueChanged<double> onProgress;
  final VoidCallback onSettings;
  final VoidCallback onBreakdown;
  final ValueChanged<String>? onChat;

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
      context.l10n.meaningCopiedReadyToPaste,
      bottom: MediaQuery.paddingOf(context).bottom + 68,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(groupAiStreamProvider(widget.group));
    // Content text follows Aa; changing the settings carries over without closing the sheet.
    final prefs = ref.watch(readerPrefsProvider).value ?? const ReaderPrefs();
    final typo = ReaderTypography(prefs, Theme.of(context).brightness);
    void retry() => ref.invalidate(groupAiStreamProvider(widget.group));
    final usingSubsidy = ref.watch(aiSourceProvider).value != AiSource.own;
    return switch (ai) {
      AiStream(
        phase: AiPhase.failed,
        error: AiException(error: AiError.noApiKey),
      ) =>
        _NoKey(onClose: _close, onSettings: widget.onSettings),
      AiStream(phase: AiPhase.failed, :final error)
          when subsidyFailureOf(error, usingSubsidy: usingSubsidy) != null =>
        _Quota(
          kind: subsidyFailureOf(error, usingSubsidy: usingSubsidy)!,
          onClose: _close,
          onUseOwnKey: () => openOwnKeySettings(context, ref, closeSheet: true),
        ),
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
        onChat: widget.onChat == null
            ? null
            : () => widget.onChat!(ai.draft.translations.join('\n\n')),
        breakdown: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s3,
          children: [
            _BreakdownEntry(
              group: widget.group,
              fade: !ai.cached,
              onTap: widget.onBreakdown,
            ),
          ],
        ),
      ),
    };
  }

  /// Small code for debugging in the error state.
  String _errorCode(Object error) => switch (error) {
    AiException(error: AiError.timeout) => context.l10n.meaningTimeoutSeconds,
    AiException(error: AiError.network) =>
      context.l10n.meaningOfflineDisconnected,
    AiException(error: AiError.http, :final status)
        when status == 401 || status == 403 =>
      context.l10n.meaningHttpKeyRejected(status ?? 0),
    AiException(error: AiError.http, status: 402) =>
      context.l10n.meaningHttpNoCredit,
    AiException(error: AiError.http, :final status) => 'HTTP $status',
    AiException(error: AiError.invalidResponse) =>
      context.l10n.meaningInvalidAiResponse,
    _ => 'error',
  };
}

/// Skeleton of all states: content scrolls at the sheet height (528) with 91 top /
/// 102 bottom padding, with the header + grabber + buttons as layers above it (board
/// Ngumpet · Opsi A). The scroll view uses the controller from
/// DraggableScrollableSheet (`PrimaryScrollController`), so dragging down at offset 0
/// closes the sheet. [hideable]: the header and buttons hide as the finger scrolls
/// ([MeaningChrome]).
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

  /// Aa text margin. The base sheet padding (24) is its lower bound; the content is
  /// only widened when the margin is larger ("Lega" 32).
  final double margin;
  final double gap;
  final bool hideable;

  /// Streaming: the buttons are locked visible and the header moves 1:1 with the
  /// content, as if part of the scrolling content.
  final bool locked;

  /// No text yet (waiting for a token): the content can't scroll. Closing still works
  /// via X, the grabber, or a tap above the sheet.
  final bool frozen;

  /// Distance of the content from the sheet top (room for the layered header).
  final double topInset;

  @override
  State<_ScrollFrame> createState() => _ScrollFrameState();
}

class _ScrollFrameState extends State<_ScrollFrame>
    with TickerProviderStateMixin {
  late final _chrome = MeaningChrome(vsync: this);

  /// The scroll came from the finger (not a programmatic scroll).
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

  /// Never hides when VoiceOver is on, in a non-result state, or while streaming.
  /// After streaming, a header that has already scrolled out stays out (the normal
  /// hiding rule continues).
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
    // Header anchor point: below the grabber (top padding 10 + 5 + 16).
    final headerTop = Layout.artinyaHeader - Space.s4 - Layout.touch;
    final headerBottom = Layout.artinyaHeader - Space.s4; // header is 44 tall
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          // The content edge follows the chrome animation: the top fade starts below the
          // header (or below the grabber when the header is hidden), the bottom fade only
          // exists while the buttons are visible; buttons hidden = edge-to-edge.
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
                // Buttons + safe area (86) are transparent, with a 20pt fade right above them.
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

/// Slides [child] by [travel] following [animation] (0 visible, 1 hidden). Reduce
/// motion: no sliding, fade only. A hidden child can't be tapped and isn't read by
/// VoiceOver.
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

/// Translation + meaning, from waiting for a token to done (board "Artinya
/// streaming · Opsi B" + "· perilaku"), or complete immediately when from cache.
/// One widget for all phases, so there is no layout jump on completion and the
/// scroll position is not reset.
///
/// - Text appears following [Pacer], per frame. Reduce motion: one whole part at a
///   time (one paragraph, then the meaning), without fading.
/// - The tip of the text being written: the last 4 words get progressively more
///   transparent, static. When done it fades slowly to solid. (Deviation from the
///   board: no per-chunk fade-in, one mechanism only.)
/// - While unfinished: the buttons are locked visible. The content is not scrolled
///   automatically: it stays at the start of the translation so it can be read from
///   the top while the rest is written (a deviation from the board, which follows
///   down).
/// - Too slow: a card above the content. Cut off: the text received so far + a banner,
///   the placeholder is dropped.
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
    this.onChat,
  });

  final ReaderTypography typo;
  final AiStream ai;
  final bool copied;
  final VoidCallback onCopy;
  final VoidCallback? onNext;
  final ValueChanged<double> onProgress;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  /// Bedahin entry, the last content item; only when the answer is complete.
  final Widget breakdown;
  final VoidCallback? onChat;

  @override
  State<_Answer> createState() => _AnswerState();
}

class _AnswerState extends State<_Answer> with TickerProviderStateMixin {
  final _pacer = Pacer();
  late final _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  int _shown = 0;

  /// Text tip: 0 = faded, 1 = solid.
  late final _solid = AnimationController(
    vsync: this,
    duration: Motion.tailFade,
  );

  /// The answer is complete and all its letters are shown.
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

  /// Starts the ticker as soon as there are letters; cut off = show everything that
  /// arrived. From cache = complete right away, with no rhythm and no following down.
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
          context.l10n.meaningTranslationAndMeaningComplete,
          TextDirection.ltr,
        );
      }
    }
  }

  /// Box of each translation: the last end decides how far the translation has been
  /// read.
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

  /// Syncs sheet → card content: the translation reading progress, 0 at the sheet start
  /// to 1 when the bottom of the last translation reaches the bottom edge of the content
  /// area. The meaning block is not counted: past it the progress stays 1. Linear in
  /// the scroll, so it follows the finger, and it also applies to a group of one long paragraph.
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
    // Scroll done so far + what remains = the total until the translation is read.
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

  /// What may be shown now.
  AiDraft _visible() {
    final draft = _ai.draft;
    if (_finished || _cut) return draft;
    if (!MediaQuery.disableAnimationsOf(context)) return draft.take(_shown);
    // Reduce motion: only the parts that are already complete.
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
    // The last visible part = the one being written (its tip is faded).
    final lastMeaning = draft.meaning != null;
    final last = lastMeaning ? -1 : draft.translations.length - 1;

    Widget text(String t, {required bool isLast}) {
      if (!isLast) return Text(t, style: style);
      final faded = !_cut && !reduced;
      return ExcludeSemantics(
        // VoiceOver reads per completed part, not per letter.
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
        label: writing
            ? context.l10n.meaningWritingTranslationAndMeaning
            : null,
        child: _ScrollFrame(
          margin: typo.margin,
          hideable: true,
          locked: writing,
          frozen: thinking,
          header: _Title(
            thinking
                ? context.l10n.meaningHangOnThinking
                : context.l10n.meaningHereSWhatItMeans,
            closeLabel: writing
                ? context.l10n.meaningCancel
                : context.l10n.sheetClose,
            onClose: widget.onClose,
          ),
          content: [
            if (_ai.phase == AiPhase.slow)
              _SlowCard(onCancel: widget.onClose, onRetry: widget.onRetry),
            _Section(
              tag: Tag.section(context.l10n.meaningTranslation),
              // One block per paragraph, so the dialogue pauses match the original.
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
                tag: Tag.section(
                  context.l10n.meaningWhatTheAuthorMeans,
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
            if (_finished && widget.onChat != null) ...[
              CircleButton(
                semanticLabel: widget.copied
                    ? context.l10n.meaningCopied
                    : context.l10n.aiCopy,
                icon: widget.copied ? AppIcons.check : AppIcons.copy,
                size: Layout.chatComposer,
                onPressed: widget.onCopy,
              ),
              AppButton.secondary(
                label: context.l10n.meaningAskAboutThis,
                icon: AppIcons.chat,
                onPressed: widget.onChat,
              ),
            ] else
              AnimatedSwitcher(
                duration: reduced ? Duration.zero : Motion.statusSwap,
                child: writing && !_cut && _ai.phase != AiPhase.slow
                    ? StatusButton(
                        key: ValueKey(thinking),
                        label: thinking
                            ? context.l10n.meaningThinking
                            : context.l10n.meaningWriting,
                      )
                    : AppButton.secondary(
                        key: const ValueKey('copy'),
                        label: widget.copied
                            ? context.l10n.meaningCopied
                            : context.l10n.aiCopy,
                        icon: widget.copied ? AppIcons.check : AppIcons.copy,
                        onPressed: _finished ? widget.onCopy : null,
                      ),
              ),
            Expanded(
              // Disabled while still processing; active again when done / cut off.
              child: AppButton.primary(
                label: context.l10n.meaningNext,
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

/// Placeholder for one part not yet written, about as tall as its eventual text (follows
/// Aa): rows from [placeholderRows], row height = text line height.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.chars, required this.style});

  final double chars;
  final TextStyle style;

  /// Average letter width per font + size, measured once.
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

/// 15 seconds without a token. The request keeps running; when a token arrives the card
/// disappears on its own.
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
        title: context.l10n.meaningTakingALittleLonger,
        body: context.l10n.meaningTheAiIsStillThinkingGive,
        actions: [
          Expanded(
            child: AppButton.secondary(
              label: context.l10n.dialogCancel,
              height: 40,
              onPressed: onCancel,
            ),
          ),
          Expanded(
            child: AppButton.primary(
              label: context.l10n.meaningTryAgain,
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

/// Connection dropped / stalled midway: what has arrived stays above it.
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
        title: context.l10n.meaningCutOffHalfway,
        body: context.l10n.meaningTheConnectionDroppedWhileWritingWhat,
        actions: [
          Expanded(
            child: AppButton.primary(
              label: context.l10n.meaningTryAgain,
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

/// Icon box in the corner of the error / empty API key states, and the content spacing
/// below it: the content starts [_tileInset] from the sheet top (below the box, roomy).
const _tileInset =
    Layout.artinyaHeader - Space.s4 - Layout.touch + IconTile.size + Space.s6;

/// Header of the error / empty API key states: icon box on the left, close on the right.
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
        semanticLabel: context.l10n.sheetClose,
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
      label: context.l10n.meaningCouldnTGetTheMeaning,
      child: _ScrollFrame(
        gap: 14,
        topInset: _tileInset,
        header: _TileHeader(
          tile: IconTile(icon: AppIcons.offline, bg: c.pink, fg: c.onPink),
          onClose: onClose,
        ),
        content: [
          _Message(
            title: context.l10n.meaningSomethingWentWrong,
            body: context.l10n.meaningTheConnectionMightBeDownOr,
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
          AppButton.secondary(
            label: context.l10n.meaningMaybeLater,
            onPressed: onClose,
          ),
          Expanded(
            child: AppButton.primary(
              label: context.l10n.meaningTryAgain,
              icon: AppIcons.retry,
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

/// Free quota used up / access revoked (board Kuota AI 08, 12).
class _Quota extends StatelessWidget {
  const _Quota({
    required this.kind,
    required this.onClose,
    required this.onUseOwnKey,
  });

  final SubsidyFailure kind;
  final VoidCallback onClose;
  final VoidCallback onUseOwnKey;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    final banned = kind == SubsidyFailure.banned;
    return _ScrollFrame(
      gap: 14,
      topInset: _tileInset,
      header: _TileHeader(
        tile: banned
            ? IconTile(icon: AppIcons.lock, bg: c.pink, fg: c.onPink)
            : IconTile(icon: AppIcons.sunrise, bg: c.accent, fg: c.onAccent),
        onClose: onClose,
      ),
      content: [
        if (banned)
          QuotaBannedCard(onUseOwnKey: onUseOwnKey, onOk: onClose)
        else
          QuotaExhaustedCard(
            now: DateTime.now(),
            onUseOwnKey: onUseOwnKey,
            onOk: onClose,
          ),
      ],
      actions: const [],
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
        _Message(
          title: context.l10n.meaningAddYourApiKeyFirst,
          body: context.l10n.meaningTranslationsAndMeaningsUseAiThrough,
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: context.l10n.meaningDonTHaveOneCreateIt),
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
        AppButton.secondary(
          label: context.l10n.meaningMaybeLater,
          onPressed: onClose,
        ),
        Expanded(
          child: AppButton.primary(
            label: context.l10n.meaningOpenSettings,
            icon: AppIcons.next,
            iconAfter: true,
            onPressed: onSettings,
          ),
        ),
      ],
    );
  }
}

/// "Masih bingung? Bedahin" at the end of the sheet content (board Opsi C · C1, state
/// B3 / B4): already broken down = "Buka bedahan · N bagian". Shown only when the meaning
/// is complete, with a 150ms fade after a stream. Waits for the part count from the DB
/// first so the copy does not change before the eyes.
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
    final title = opened
        ? context.l10n.meaningOpenBreakdown
        : context.l10n.meaningStillPuzzledBreakItDown;
    final subtitle = opened
        ? context.l10n.meaningPreviouslyBrokenDown(
            sections == 1
                ? context.l10n.breakdownIdea
                : context.l10n.breakdownSections(sections),
          )
        : context.l10n.meaningSectionBySectionPlusPeopleTerms;
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
