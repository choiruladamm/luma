import 'package:flutter/material.dart';

import '../theme/stabilo_theme.dart';

/// Logo "Senyum Stabilo": coretan stabilo jadi huruf u + titik pink.
class LumaLogo extends StatelessWidget {
  const LumaLogo({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.stabilo;
    return Semantics(
      label: 'Luma',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _LogoPainter(ink: c.ink, accent: c.accent, pink: c.pink),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({
    required this.ink,
    required this.accent,
    required this.pink,
  });

  final Color ink, accent, pink;

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
    canvas
      ..drawPath(smile, stroke(ink, 28))
      ..drawPath(smile, stroke(accent, 20))
      ..drawCircle(const Offset(50, 22), 9, Paint()..color = pink)
      ..drawCircle(const Offset(50, 22), 9, stroke(ink, 4));
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.ink != ink || old.accent != accent || old.pink != pink;
}
