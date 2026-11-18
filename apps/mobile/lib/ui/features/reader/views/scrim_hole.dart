import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_tokens.dart';

/// Scrim of the Artinya sheet, with a hole over the group block.
class ScrimHole extends CustomPainter {
  ScrimHole({required this.color, required this.hole, super.repaint});

  final Color color;
  final Rect? Function() hole;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    final h = hole();
    if (h != null) {
      path.addRRect(
        RRect.fromRectAndRadius(h, const Radius.circular(Radii.md)),
      );
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  // The hole is re-measured on every paint (scroll / highlight moves).
  @override
  bool shouldRepaint(ScrimHole old) => true;
}
