import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../domain/models/book.dart';
import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';

/// Fixed yellow card while the Artinya sheet is open (the page does not move): a window
/// at the group position whose content is the group text, scrolled as far as the
/// translation has been read. Mounted only when the group is too long (the bottom
/// of its text is covered by the sheet): a group that fits has nothing to scroll.
///
/// Mounted in the same Stack as the chapter text (`show` coordinates are that
/// Stack's). Empty until [MeaningPinCardState.show] is called.
class MeaningPinCard extends StatefulWidget {
  const MeaningPinCard({
    super.key,
    required this.marginWidth,
    required this.gap,
    required this.style,
  });

  final double marginWidth;

  /// Spacing between paragraphs.
  final double gap;

  /// Text style on top of the highlight.
  final TextStyle style;

  @override
  State<MeaningPinCard> createState() => MeaningPinCardState();
}

class MeaningPinCardState extends State<MeaningPinCard> {
  ({Rect rect, List<ReaderParagraph> paras})? _pin;
  final _scroll = ScrollController();
  final _view = GlobalKey();
  final _keys = <int, GlobalKey>{};
  Future<void>? _unpinning;

  void show(Rect rect, List<ReaderParagraph> paras) =>
      setState(() => _pin = (rect: rect, paras: paras));

  /// Closes the fixed card: its content returns to the start first so it does not
  /// jump onto the page text below. Called twice (the sheet starts closing, the sheet
  /// is gone); both calls wait for the same process.
  Future<void> unpin({bool animate = true}) => _pin == null
      ? Future.value()
      : _unpinning ??= _unpin(animate).whenComplete(() => _unpinning = null);

  Future<void> _unpin(bool animate) async {
    if (animate && _scroll.hasClients && _scroll.offset > 0.5) {
      await _scroll.animateTo(
        0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.sheetClose,
        curve: Curves.easeOut,
      );
    }
    if (mounted) setState(() => _pin = null);
  }

  /// Syncs sheet → card: [progress] (0–1) = how far the translation has been read.
  /// 0 = start position, 1 = the bottom of the group text sits exactly
  /// [Layout.followGap] above the sheet. Linear in between, chased by a short animation.
  void follow(double progress, double sheetTop) {
    final view = _view.currentContext?.findRenderObject();
    final pin = _pin;
    final last = pin == null
        ? null
        : _keys[pin.paras.last.index]?.currentContext?.findRenderObject();
    if (view is! RenderBox || last is! RenderBox || !_scroll.hasClients) {
      return;
    }
    final viewTop = view.localToGlobal(Offset.zero).dy;
    final shown = sheetTop - Layout.followGap - viewTop; // visible height
    final textBottom =
        last.localToGlobal(Offset.zero).dy -
        viewTop +
        _scroll.offset +
        last.size.height;
    final needed = (textBottom - shown).clamp(0.0, double.infinity);
    final target = (progress * needed).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
      return;
    }
    // Chased smoothly instead of jumping: each update restarts a short animation from
    // the current position, so a fling on the sheet does not make the text jerk.
    unawaited(
      _scroll.animateTo(target, duration: Motion.follow, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pin = _pin;
    if (pin == null) {
      // The parent Stack may only hold Positioned children: its size is not affected.
      return const Positioned(width: 0, height: 0, child: SizedBox.shrink());
    }
    final c = context.stabilo;
    return Positioned.fromRect(
      key: const ValueKey('pinned-group'),
      rect: pin.rect,
      child: IgnorePointer(
        child: ClipRRect(
          key: _view,
          // Straight bottom: the card continues below the sheet and merges with the page
          // card, instead of a box that stops above the sheet.
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.md),
          ),
          // Canvas first: the dark highlight is translucent, and without this the page text
          // behind it would show doubled.
          child: ColoredBox(
            color: c.canvas,
            child: ColoredBox(
              color: c.highlight,
              child: SingleChildScrollView(
                controller: _scroll,
                physics: const NeverScrollableScrollPhysics(),
                // Bottom as wide as the distance to the sheet: the last paragraph can scroll up
                // until it is fully visible above the sheet.
                padding: EdgeInsets.fromLTRB(
                  widget.marginWidth / 2,
                  Space.s2,
                  widget.marginWidth / 2,
                  Layout.followGap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: widget.gap,
                  children: [
                    for (final p in pin.paras)
                      KeyedSubtree(
                        key: _keys.putIfAbsent(p.index, GlobalKey.new),
                        child: Text(p.text, style: widget.style),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
