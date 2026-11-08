import 'package:flutter/material.dart';

import '../../../core/theme/stabilo_tokens.dart';

/// Scrim sheet Artinya yang bolong di blok grup.
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

  // Bolongnya diukur ulang tiap paint (scroll / highlight pindah).
  @override
  bool shouldRepaint(ScrimHole old) => true;
}
