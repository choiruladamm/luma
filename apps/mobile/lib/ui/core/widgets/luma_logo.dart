import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';

/// "Senyum Stabilo" logo: a stabilo stroke forming the letter u + a pink dot.
///
/// Default = the finished logo. For the splash animation: [draw] 0..1 = how
/// much of the u stroke is drawn (left to right), [dot] = pink dot scale (0 =
/// absent, may exceed 1 for a pop effect), [shadow] 0..1 = offset-4 shadow
/// behind the stroke (board Splash light; header & dark mode have none).
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
    // Drawn on a 100×100 grid like the original SVG.
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
