import 'package:flutter/material.dart';

import '../../../domain/models/markdown_shelf.dart';
import '../theme/stabilo_tokens.dart';

/// Chapter strip of a Markdown book (board Import Markdown 49): one slot per
/// chapter number from 1 to the highest imported. Highest number >
/// [MarkdownShelf.maxSlots] = a single bar. Height follows the parent.
///
/// - [done]: chapter already read, and the fill of the chapter being read.
/// - [todo]: chapter imported but not read yet.
/// - [missing]: dashed line for a chapter not imported.
/// - [track]: fallback bar background; null = follows the strip background.
class ChapterSlots extends StatelessWidget {
  const ChapterSlots({
    super.key,
    required this.shelf,
    required this.gap,
    required this.done,
    required this.todo,
    required this.missing,
    this.track,
    this.radius = 0,
  });

  final MarkdownShelf shelf;
  final double gap;
  final Color done, todo, missing;
  final Color? track;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    if (shelf.collapsed) {
      return DecoratedBox(
        decoration: BoxDecoration(color: track, borderRadius: r),
        child: ClipRRect(
          borderRadius: r,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: shelf.barFraction,
              heightFactor: 1,
              child: ColoredBox(color: done),
            ),
          ),
        ),
      );
    }
    return Row(
      spacing: gap,
      children: [
        for (final s in shelf.slots)
          Expanded(
            child: switch (s) {
              SlotState.missing => CustomPaint(
                painter: _Dashes(missing),
                child: const SizedBox.expand(),
              ),
              SlotState.read => _fill(done, r),
              SlotState.unread => _fill(todo, r),
              SlotState.reading => ClipRRect(
                borderRadius: r,
                child: ColoredBox(
                  color: todo,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: shelf.fraction.clamp(0, 1),
                      heightFactor: 1,
                      child: ColoredBox(color: done),
                    ),
                  ),
                ),
              ),
            },
          ),
      ],
    );
  }

  Widget _fill(Color color, BorderRadius r) => DecoratedBox(
    decoration: BoxDecoration(color: color, borderRadius: r),
  );
}

/// Dashed 2/2 line in the middle of an empty slot.
class _Dashes extends CustomPainter {
  const _Dashes(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 2.0, gap = 2.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = Layout.outline;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(0, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}
