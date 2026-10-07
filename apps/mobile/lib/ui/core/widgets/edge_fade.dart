import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/stabilo_tokens.dart';

/// Profil fade satu tepi, diukur dari tepi area scroll ke dalam:
/// [clear] kosong total → [hold] di opacity [floor] → [fade] naik ke penuh.
/// Standar cuma [fade]; layar baca pake [clear] (status bar / bawah garis
/// progres) dan [hold] (teks di belakang kapsul).
@immutable
class EdgeFadeSide {
  const EdgeFadeSide(
    this.fade, {
    this.clear = 0,
    this.hold = 0,
    this.floor = 0,
  });

  static const none = EdgeFadeSide(0);

  /// Sheet & fade atas layar penuh (board EdgeFade: standar 20pt).
  static const standard = EdgeFadeSide(20);

  /// Bawah layar penuh (Rak, Pengaturan): 34pt = safe area home indicator.
  static const screenBottom = EdgeFadeSide(34);

  final double fade;
  final double clear;
  final double hold;

  /// Opacity minimum isi di [hold] dan awal [fade].
  final double floor;

  double get extent => clear + hold + fade;

  static EdgeFadeSide lerp(EdgeFadeSide a, EdgeFadeSide b, double t) =>
      EdgeFadeSide(
        lerpDouble(a.fade, b.fade, t)!,
        clear: lerpDouble(a.clear, b.clear, t)!,
        hold: lerpDouble(a.hold, b.hold, t)!,
        floor: lerpDouble(a.floor, b.floor, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is EdgeFadeSide &&
      other.fade == fade &&
      other.clear == clear &&
      other.hold == hold &&
      other.floor == floor;

  @override
  int get hashCode => Object.hash(fade, clear, hold, floor);
}

/// Tepi area scroll mudar halus (board EdgeFade · tepi area scroll). Mask,
/// bukan gradien warna latar: isinya yang transparan, aman di terang & gelap.
/// Fade atas cuma kalau udah di-scroll, fade bawah cuma kalau masih ada isi
/// di bawah; muncul/ilang 150ms. Kondisinya dibaca dari notifikasi scroll
/// [child], jadi gak butuh ScrollController.
class EdgeFadeScroll extends StatefulWidget {
  const EdgeFadeScroll({
    super.key,
    this.top = EdgeFadeSide.standard,
    this.bottom = EdgeFadeSide.standard,
    required this.child,
  });

  final EdgeFadeSide top;
  final EdgeFadeSide bottom;

  /// Scroll view (atau yang ngebungkus satu scroll view).
  final Widget child;

  @override
  State<EdgeFadeScroll> createState() => EdgeFadeScrollState();
}

class EdgeFadeScrollState extends State<EdgeFadeScroll> {
  bool _topOn = false;
  bool _bottomOn = false;

  /// Lagi ada isi di atas / di bawah yang kepotong.
  @visibleForTesting
  ({bool top, bool bottom}) get debugEdges => (top: _topOn, bottom: _bottomOn);

  bool _update(ScrollMetrics m) {
    // Dikit toleransi: posisi mentok kadang meleset sepersekian piksel.
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
                final g = edgeFadeStops(
                  rect.height,
                  top: widget.top,
                  bottom: widget.bottom,
                  topOn: top,
                  bottomOn: bottom,
                );
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
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

/// Titik gradien mask buat area setinggi [height]. [topOn]/[bottomOn] 0..1
/// (lagi animasi muncul/ilang). Area lebih pendek dari total fade → semua
/// jarak dikecilin proporsional, stop tetep urut.
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

  // (jarak dari tepi, opacity) dari tepi ke dalam.
  List<(double, double)> profile(EdgeFadeSide s, double on) {
    if (s.extent <= 0) return const [(0, 1)];
    double a(double v) => 1 - on * (1 - v);
    return [
      (0, a(s.clear > 0 ? 0 : s.floor)),
      if (s.clear > 0) ...[(s.clear * k, a(0)), (s.clear * k, a(s.floor))],
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
