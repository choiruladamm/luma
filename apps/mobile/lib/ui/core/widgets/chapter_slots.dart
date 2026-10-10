import 'package:flutter/material.dart';

import '../../../domain/models/markdown_shelf.dart';
import '../theme/stabilo_tokens.dart';

/// Strip bab buku Markdown (board Import Markdown 49): satu slot per nomor
/// bab dari 1 sampai nomor tertinggi yang udah masuk. Nomor tertinggi >
/// [MarkdownShelf.maxSlots] = satu bar aja. Tingginya ikut parent.
///
/// - [done]: bab udah dibaca, dan isi bab yang lagi dibaca.
/// - [todo]: bab udah masuk tapi belum dibaca.
/// - [missing]: garis putus di bab yang belum di-import.
/// - [track]: latar bar fallback; null = ikut latar strip.
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

/// Garis putus 2/2 di tengah slot kosong.
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
