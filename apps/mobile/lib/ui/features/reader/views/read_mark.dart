import 'package:luma/l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_theme.dart';
import '../../../core/theme/stabilo_tokens.dart';

/// Momentary mark in the chapter body: a highlighter flash on the group at the saved
/// position ("Lanjut baca") or on a Cari kata result paragraph. With reduce
/// motion: a 4pt left line that disappears on its own.
///
/// Placed in the chapter body Stack (`show` coordinates are that Stack's), empty
/// until [ReadMarkState.show] is called.
class ReadMark extends StatefulWidget {
  const ReadMark({super.key});

  @override
  State<ReadMark> createState() => ReadMarkState();
}

class ReadMarkState extends State<ReadMark>
    with SingleTickerProviderStateMixin {
  Rect? _rect;
  Timer? _timer;
  late final _flash = AnimationController(vsync: this, duration: Motion.flash)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() => _rect = null);
    });

  /// 0 → 60% → 0 (board: holds at the peak, falls slowly).
  static final _curve = TweenSequence<double>([
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

  /// Tandai [target] (koordinat Stack) selama [duration].
  void show(Rect target, Duration duration) {
    _timer?.cancel();
    setState(
      () => _rect = Rect.fromLTRB(
        target.left - Space.s3,
        target.top - Space.s2,
        target.right + Space.s3,
        target.bottom + Space.s2,
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _timer = Timer(Motion.flashReduced, () {
        if (mounted) setState(() => _rect = null);
      });
    } else {
      _flash.duration = duration;
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    if (rect == null) {
      // The parent Stack has other children: its size is not affected.
      return const Positioned(width: 0, height: 0, child: SizedBox.shrink());
    }
    final c = context.stabilo;
    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        label: context.l10n.readYouLastReadHere,
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
                      alpha: c.flash.a * _curve.evaluate(_flash),
                    ),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
              ),
      ),
    );
  }
}
