import 'package:luma/l10n/l10n.dart';

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/scroll_run.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';
import '../../../core/theme/stabilo_type.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/edge_fade.dart';

// Immersive reading page (board Baca imersif · ReaderCapsule). Sizes here are
// measured from the safe area (board: top 54, bottom 34).

/// Top capsule: 6 below the top safe area, 58 tall.
const capsuleTopGap = 6.0;
const capsuleHeight = 58.0;

/// Bottom capsule: 14 above the bottom safe area, 40 tall.
const capsuleBottomGap = 14.0;
const capsuleBottomHeight = 40.0;

double readerDockHeight(BuildContext context) => Layout.chatHeader;

/// Chapter-opening text starts here (board: 140) so the title isn't covered.
const readerTextTop = 86.0;

/// Empty space below the last text (board: 100 from the screen edge).
const readerTextBottom = 66.0;

/// Edge fade of the reading text (board EdgeFade · variant Baca). [t] is
/// `ReaderChrome.hidden` (0 capsules visible, 1 immersive), so the fade strength
/// follows the capsule animation. Capsules visible: the status bar is clear, text
/// behind the capsule is ~18% faded down to the bottom screen edge, and fully
/// opaque 48pt from the capsule edge. Immersive: no fade at all, text passes under
/// the progress line up to the edge.
({EdgeFadeSide top, EdgeFadeSide bottom}) readerEdgeFade(
  EdgeInsets pad,
  double t, {
  double bottomHeight = capsuleBottomHeight,
}) {
  final behind = lerpDouble(0.18, 1, t)!;
  return (
    top: EdgeFadeSide(
      48,
      clear: pad.top,
      clearAlpha: t,
      hold: capsuleTopGap + capsuleHeight,
      floor: behind,
    ),
    bottom: EdgeFadeSide(
      48,
      hold: pad.bottom + capsuleBottomGap + bottomHeight,
      floor: behind,
    ),
  );
}

/// Hides/shows the capsules following the scroll (thresholds in [ScrollRun]):
/// scrolling down hides, scrolling up shows. While a finger drags, the capsules
/// follow 1:1 and snap on release.
class ReaderChrome {
  ReaderChrome({required TickerProvider vsync})
    : hidden = AnimationController(vsync: vsync, duration: Motion.capsule);

  /// Travel distance while following the finger: the top capsule goes past the screen edge.
  static const _travel = 120.0;

  /// 0 = visible, 1 = hidden.
  final AnimationController hidden;

  /// Current target; the status bar follows it.
  final visible = ValueNotifier(true);

  bool reduceMotion = false;

  final _run = ScrollRun();

  /// [delta] > 0 = scrolling down (text moves up).
  void scrolled(double delta, {required bool dragging}) {
    if (delta == 0) return;
    if (dragging) {
      hidden.value = (hidden.value + delta / _travel).clamp(0.0, 1.0);
    }
    switch (_run.add(delta)) {
      case ChromeIntent.hide:
        _set(false, snap: !dragging);
      case ChromeIntent.show:
        _set(true, snap: !dragging);
      case null:
    }
  }

  /// Finger released / scroll stopped: slide to the target.
  void release() => _snap();

  void show() => _set(true);
  void hide() => _set(false);
  void toggle() => _set(!visible.value);

  void _set(bool show, {bool snap = true}) {
    visible.value = show;
    _run.reset();
    if (snap) _snap();
  }

  void _snap() {
    final target = visible.value ? 0.0 : 1.0;
    if (hidden.value == target && !hidden.isAnimating) return;
    hidden.animateTo(
      target,
      duration: reduceMotion ? Duration.zero : Motion.capsule,
      curve: Curves.easeOut,
    );
  }

  void dispose() {
    hidden.dispose();
    visible.dispose();
  }
}

/// Two capsules that slide off-screen following [ReaderChrome.hidden]. Overlay:
/// the text below doesn't jump; its edges are faded by [readerEdgeFade].
class ReaderCapsules extends StatelessWidget {
  const ReaderCapsules({
    super.key,
    required this.chrome,
    required this.top,
    this.bottom,
  });

  final ReaderChrome chrome;
  final Widget top;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final topTravel = pad.top + capsuleTopGap + capsuleHeight + Space.s6;
    final bottomTravel =
        pad.bottom + capsuleBottomGap + readerDockHeight(context) + Space.s6;
    return AnimatedBuilder(
      animation: chrome.hidden,
      builder: (context, _) {
        final t = chrome.hidden.value;
        return IgnorePointer(
          ignoring: t > 0.5,
          child: Stack(
            children: [
              Positioned(
                left: Layout.margin,
                right: Layout.margin,
                top: pad.top + capsuleTopGap,
                child: Transform.translate(
                  offset: Offset(0, -t * topTravel),
                  child: top,
                ),
              ),
              if (bottom != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: pad.bottom + capsuleBottomGap,
                  child: Transform.translate(
                    offset: Offset(0, t * bottomTravel),
                    child: Center(child: bottom),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.height,
    required this.padding,
    required this.child,
  });

  final double height;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: c.sheet,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: c.capsuleLine, width: Layout.outline),
        boxShadow: Elevation.capsule(c, Theme.of(context).brightness),
      ),
      child: child,
    );
  }
}

/// Top capsule: back · title + chapter · table of contents · ⋯ (Cari kata, Atur
/// tampilan).
class ReaderTopCapsule extends StatelessWidget {
  const ReaderTopCapsule({
    super.key,
    required this.title,
    this.subtitle,
    required this.onBack,
    this.onToc,
    this.onMore,
    this.tocOpen = false,
    this.moreOpen = false,
    this.searchActive = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;

  /// Null = the table of contents can't be opened yet (book not read).
  final VoidCallback? onToc;

  /// Null = book not read yet.
  final VoidCallback? onMore;

  /// The table-of-contents sheet or ⋯ menu (or a sheet opened from the menu) is
  /// open: the button is yellow.
  final bool tocOpen;
  final bool moreOpen;

  /// Search mode (Cari kata) is on: ⋯ gets a small yellow dot.
  final bool searchActive;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      container: true,
      label: context.l10n.readerReadingMenu,
      child: _Pill(
        height: capsuleHeight,
        // The 44 button sits centered in the 58 height (minus the border line).
        padding: const EdgeInsets.symmetric(horizontal: 5.5),
        child: Row(
          spacing: 6,
          children: [
            CircleButton(
              semanticLabel: context.l10n.readerBackToShelf,
              icon: AppIcons.back,
              onPressed: onBack,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 1,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StabiloType.label.copyWith(
                      fontSize: 14.5,
                      height: 1.15,
                      color: c.ink,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StabiloType.caption.copyWith(
                        fontSize: 11.5,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: c.ink2,
                      ),
                    ),
                ],
              ),
            ),
            CircleButton(
              semanticLabel: context.l10n.readerContents,
              icon: AppIcons.toc,
              active: tocOpen,
              onPressed: onToc,
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleButton(
                  semanticLabel: context.l10n.readerMoreActions,
                  icon: AppIcons.readerMore,
                  active: moreOpen,
                  onPressed: onMore,
                ),
                if (searchActive)
                  Positioned(
                    right: 5,
                    top: 5,
                    child: IgnorePointer(
                      child: Container(
                        key: const ValueKey('search-dot'),
                        width: Layout.searchDot,
                        height: Layout.searchDot,
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.ink, width: 1.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom capsule: percent + bar + time left. Informational only, not tappable.
class ReaderBottomCapsule extends StatelessWidget {
  const ReaderBottomCapsule({
    super.key,
    required this.progress,
    required this.label,
    this.compact = false,
  });

  final bool compact;

  /// Book progress 0..1.
  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return _Pill(
      height: capsuleBottomHeight,
      padding: const EdgeInsets.symmetric(horizontal: Space.s4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Text(
            '${(progress * 100).floor()}%',
            style: StabiloType.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          if (!compact)
            SizedBox(
              width: Layout.readerProgressTrack,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.full),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: c.track,
                  color: c.progressFill,
                ),
              ),
            ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StabiloType.caption.copyWith(color: c.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shares the capsules' visibility and pointer handling; progress stays informational.
class ReaderChatDock extends StatelessWidget {
  const ReaderChatDock({
    super.key,
    required this.progress,
    required this.label,
    required this.onChat,
  });
  final double progress;
  final String label;
  final VoidCallback? onChat;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Layout.margin),
    child: _Pill(
      height: Layout.chatHeader,
      padding: const EdgeInsets.only(left: Space.s4, right: Space.s1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.s2,
        children: [
          Text('${(progress * 100).floor()}%', style: StabiloType.label),
          SizedBox(
            width:
                MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                    MediaQuery.sizeOf(context).width < 350
                ? Layout.readerProgressTrack
                : Layout.readerChatProgressTrack,
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              backgroundColor: context.stabilo.track,
              color: context.stabilo.ink,
            ),
          ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StabiloType.caption,
            ),
          ),
          CircleButton(
            semanticLabel: context.l10n.readerBookChat,
            icon: AppIcons.chat,
            primary: onChat != null,
            onPressed: onChat,
          ),
        ],
      ),
    ),
  );
}

/// 2pt progress line spanning the screen width, sitting right above the bottom safe area.
class ReaderProgressLine extends StatelessWidget {
  const ReaderProgressLine({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.paddingOf(context).bottom,
      height: 2,
      child: Semantics(
        label: context.l10n.readerBookProgress,
        value: '${(progress * 100).floor()}%',
        child: ColoredBox(
          color: c.progressLineTrack,
          child: LayoutBuilder(
            builder: (context, box) => Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: math.max(6, progress.clamp(0.0, 1.0) * box.maxWidth),
                child: ColoredBox(color: c.progressLine),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
