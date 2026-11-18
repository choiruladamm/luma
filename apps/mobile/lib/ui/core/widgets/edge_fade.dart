import 'package:flutter/material.dart';

import '../theme/stabilo_tokens.dart';

/// Fade profile of one edge, measured from the scroll area's edge inward:
/// [clear] at opacity [clearAlpha] → [hold] at opacity [floor] → [fade] rising
/// to full. The default is [fade] only; the reading screen uses [clear] (status
/// bar) and [hold] (text behind the capsule).
@immutable
class EdgeFadeSide {
  const EdgeFadeSide(
    this.fade, {
    this.clear = 0,
    this.clearAlpha = 0,
    this.hold = 0,
    this.floor = 0,
  });

  /// No fade: the bottom edge of a screen/sheet that meets no button (content
  /// runs edge-to-edge to the physical edge).
  static const none = EdgeFadeSide(0);

  /// Below a pinned title/header & above an action button (default 20pt).
  static const standard = EdgeFadeSide(20);

  final double fade;
  final double clear;
  final double clearAlpha;
  final double hold;

  /// Minimum content opacity at [hold] and the start of [fade].
  final double floor;

  double get extent => clear + hold + fade;

  @override
  bool operator ==(Object other) =>
      other is EdgeFadeSide &&
      other.fade == fade &&
      other.clear == clear &&
      other.clearAlpha == clearAlpha &&
      other.hold == hold &&
      other.floor == floor;

  @override
  int get hashCode => Object.hash(fade, clear, clearAlpha, hold, floor);
}

/// Softly fades the edges of a scroll area (board EdgeFade · tepi area scroll).
/// A mask, not a background-color gradient: the content itself turns
/// transparent, safe in light & dark. The top fades only once scrolled, the
/// bottom only while content remains below; 150ms in/out. The bottom edge of a
/// screen/sheet is never faded (`bottom: EdgeFadeSide.none`) unless it meets an
/// action button or the capsule. The condition is read from [child]'s scroll
/// notifications, so no ScrollController is needed.
class EdgeFadeScroll extends StatefulWidget {
  const EdgeFadeScroll({
    super.key,
    this.top = EdgeFadeSide.standard,
    this.bottom = EdgeFadeSide.standard,
    this.axis = Axis.vertical,
    required this.child,
  });

  /// Horizontal: [top] = left edge, [bottom] = right edge.
  final EdgeFadeSide top;
  final EdgeFadeSide bottom;
  final Axis axis;

  /// Scroll view (or something wrapping one).
  final Widget child;

  @override
  State<EdgeFadeScroll> createState() => EdgeFadeScrollState();
}

class EdgeFadeScrollState extends State<EdgeFadeScroll> {
  bool _topOn = false;
  bool _bottomOn = false;

  /// Content is currently cut off above / below.
  @visibleForTesting
  ({bool top, bool bottom}) get debugEdges => (top: _topOn, bottom: _bottomOn);

  bool _update(ScrollMetrics m) {
    // Small tolerance: the end position sometimes misses by a fraction of a pixel.
    final top = m.pixels > m.minScrollExtent + 0.5;
    final bottom = m.pixels < m.maxScrollExtent - 0.5;
    if (top != _topOn || bottom != _bottomOn) {
      setState(() {
        _topOn = top;
        _bottomOn = bottom;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => n.depth == 0 && _update(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => n.depth == 0 && _update(n.metrics),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _topOn ? 1 : 0),
          duration: Motion.edgeFade,
          builder: (context, top, _) => TweenAnimationBuilder<double>(
            tween: Tween(end: _bottomOn ? 1 : 0),
            duration: Motion.edgeFade,
            builder: (context, bottom, child) => ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) {
                final across = widget.axis == Axis.horizontal;
                final g = edgeFadeStops(
                  across ? rect.width : rect.height,
                  top: widget.top,
                  bottom: widget.bottom,
                  topOn: top,
                  bottomOn: bottom,
                );
                return LinearGradient(
                  begin: across ? Alignment.centerLeft : Alignment.topCenter,
                  end: across ? Alignment.centerRight : Alignment.bottomCenter,
                  colors: [
                    for (final a in g.alphas) Colors.black.withValues(alpha: a),
                  ],
                  stops: g.stops,
                ).createShader(rect);
              },
              child: child,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Mask gradient stops for an area [height] tall. [topOn]/[bottomOn] 0..1
/// (while animating in/out). An area shorter than the total fade → all
/// distances shrink proportionally, stops stay ordered.
({List<double> stops, List<double> alphas}) edgeFadeStops(
  double height, {
  required EdgeFadeSide top,
  required EdgeFadeSide bottom,
  required double topOn,
  required double bottomOn,
}) {
  if (height <= 0) return (stops: const [0, 1], alphas: const [1, 1]);
  final total = top.extent + bottom.extent;
  final k = total > height ? height / total : 1.0;

  // (distance from edge, opacity) from the edge inward.
  List<(double, double)> profile(EdgeFadeSide s, double on) {
    if (s.extent <= 0) return const [(0, 1)];
    double a(double v) => 1 - on * (1 - v);
    return [
      (0, a(s.clear > 0 ? s.clearAlpha : s.floor)),
      if (s.clear > 0) ...[
        (s.clear * k, a(s.clearAlpha)),
        (s.clear * k, a(s.floor)),
      ],
      if (s.hold > 0) ((s.clear + s.hold) * k, a(s.floor)),
      (s.extent * k, 1),
    ];
  }

  final upper = profile(top, topOn);
  final lower = profile(bottom, bottomOn).reversed;
  return (
    stops: [
      for (final (d, _) in upper) d / height,
      for (final (d, _) in lower) 1 - d / height,
    ],
    alphas: [for (final (_, a) in upper) a, for (final (_, a) in lower) a],
  );
}
