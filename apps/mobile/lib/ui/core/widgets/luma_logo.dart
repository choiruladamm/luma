import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';

/// Logo "Senyum Stabilo": coretan stabilo jadi huruf u + titik pink.
///
/// Default = logo jadi. Buat animasi splash: [draw] 0..1 = seberapa jauh
/// coretan u digambar (kiri ke kanan), [dot] = skala titik pink (0 = belum
/// ada, boleh > 1 buat efek pop), [shadow] 0..1 = bayangan offset 4 di
/// belakang coretan (board Splash terang; header & mode gelap tanpa).
class LumaLogo extends StatelessWidget {
  const LumaLogo({
    super.key,
    this.size = 28,
    this.draw = 1,
    this.dot = 1,
    this.shadow = 0,
  });

  final double size;
  final double draw;
  final double dot;
  final double shadow;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      label: 'Luma',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _LogoPainter(
          ink: c.ink,
          accent: c.accent,
          pink: c.pink,
          draw: draw,
          dot: dot,
          shadow: shadow,
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({
    required this.ink,
    required this.accent,
    required this.pink,
    required this.draw,
    required this.dot,
    required this.shadow,
  });

  final Color ink, accent, pink;
  final double draw, dot, shadow;

  @override
  void paint(Canvas canvas, Size size) {
    // Digambar di grid 100×100 kayak SVG aslinya.
    canvas.scale(size.width / 100);
    final smile = Path()
      ..moveTo(26, 34)
      ..cubicTo(26, 72, 74, 72, 74, 34);
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.square;
    if (draw > 0) {
      final metric = smile.computeMetrics().first;
      final drawn = draw >= 1
          ? smile
          : metric.extractPath(0, metric.length * draw);
      if (shadow > 0) {
        canvas
          ..save()
          ..translate(4 * shadow, 4 * shadow)
          ..drawPath(drawn, stroke(ink, 28))
          ..restore();
      }
      canvas
        ..drawPath(drawn, stroke(ink, 28))
        ..drawPath(drawn, stroke(accent, 20));
    }
    if (dot > 0) {
      canvas
        ..save()
        ..translate(50, 22)
        ..scale(dot)
        ..translate(-50, -22)
        ..drawCircle(const Offset(50, 22), 9, Paint()..color = pink)
        ..drawCircle(const Offset(50, 22), 9, stroke(ink, 4))
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.ink != ink ||
      old.accent != accent ||
      old.pink != pink ||
      old.draw != draw ||
      old.dot != dot ||
      old.shadow != shadow;
}
